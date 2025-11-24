# Load feed data
feed_data <- read_csv("data/FICD 2025-10-27.csv")

# Select relevant columns
feed_data <- feed_data[, c("Description", "Crude  Protein (%)", "Gross Energy -MJ (MJ/kg)")]
feed_data <- na.omit(feed_data)
names(feed_data) <- c("Ingredient", "Protein", "Energy")


server <- function(input, output, session) {

  output$feed_table <- renderDT({
    datatable(feed_data)
  })

  observeEvent(input$formulate, {
    # Objective: minimize total weight (no cost)
    f.obj <- rep(1, nrow(feed_data))

    # Nutrient matrix
    f.con <- rbind(feed_data$Protein, feed_data$Energy)
    f.dir <- c(">=", ">=")
    f.rhs <- c(input$protein_req, input$energy_req)


    # Solve LP----
    result <- lp(
      "min",
      f.obj,
      f.con,
      f.dir,
      f.rhs
      )

    if (result$status == 0) {
      amounts <- result$solution
      names(amounts) <- feed_data$Ingredient
      output$solution_text <- renderPrint({
        cat("Optimal Feed Mix (kg):\n")
        print(round(amounts, 2))
        cat("\nTotal Feed Weight (kg):", round(result$objval, 2))
      })
    } else {
      output$solution_text <- renderPrint({
        cat("No feasible solution found. Try adjusting the requirements.")
      })
    }
  })
}
