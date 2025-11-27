# Load data----


server <- function(input, output, session) {

  # TABLE: All feed ingredients----
  output$feed_table <- renderDT({
    datatable(feed_data, selection = "multiple")  # Allow multiple row selection
  })





  # TABLE: Selected feed ingredients----
  output$selected_feed_table <- renderDT({
    selected_rows <- input$feed_table_rows_selected
    if (length(selected_rows) > 0) {
      datatable(feed_data[selected_rows, ])
    } else {
      datatable(data.frame(Message = "No ingredients selected"))
    }
  })





  observeEvent(input$formulate, {



    selected_rows <- input$feed_table_rows_selected

    if (length(selected_rows) == 0) {
      output$solution_text <- renderPrint({
        cat("Please select at least one ingredient from the table.")
      })
      return(NULL)
    }

    # Filter feed_data based on selection
    selected_feed <- feed_data[selected_rows, ]

    # LP setup
    f.obj <- rep(1, nrow(selected_feed))
    f.con <- rbind(selected_feed$Protein, selected_feed$Energy)
    f.dir <- c(">=", ">=")
    f.rhs <- c(input$protein_req, input$energy_req)



    # Solve LP----
    result <- lp(
      direction = "min",
      objective.in = f.obj,
      const.mat = f.con,
      const.dir = f.dir,
      const.rhs = f.rhs
      )

    if (result$status == 0) {
      amounts <- result$solution
      names(amounts) <- selected_feed$Ingredient
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
