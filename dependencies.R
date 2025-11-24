library(shiny)
library(lpSolve)
library(DT)

# Sample ingredient data
ingredients <- data.frame(
  Name = c("Corn", "Soybean Meal", "Wheat Bran"),
  Cost = c(0.3, 0.5, 0.25),
  Protein = c(8, 44, 15),
  Energy = c(14, 12, 10)
)

ui <- fluidPage(
  titlePanel("Linear Feed Formulation"),

  sidebarLayout(
    sidebarPanel(
      numericInput("protein_req", "Protein Requirement (%)", value = 16),
      numericInput("energy_req", "Energy Requirement (MJ/kg)", value = 13),
      actionButton("formulate", "Formulate Feed")
    ),

    mainPanel(
      DTOutput("ingredient_table"),
      verbatimTextOutput("solution_text")
    )
  )
)

server <- function(input, output, session) {

  output$ingredient_table <- renderDT({
    datatable(ingredients, editable = FALSE)
  })

  observeEvent(input$formulate, {
    # Objective: minimize cost
    cost <- ingredients$Cost

    # Nutrient matrix
    nutrient_matrix <- rbind(
      ingredients$Protein,
      ingredients$Energy
    )

    # Requirements
    requirements <- c(input$protein_req, input$energy_req)

    # Directions
    directions <- c(">=", ">=")

    # Solve LP
    result <- lp("min", cost, nutrient_matrix, directions, requirements)

    if (result$status == 0) {
      amounts <- result$solution
      names(amounts) <- ingredients$Name
      output$solution_text <- renderPrint({
        cat("Optimal Feed Mix (kg):\n")
        print(round(amounts, 2))
        cat("\nTotal Cost (per kg):", round(result$objval, 2))
      })
    } else {
      output$solution_text <- renderPrint({
        cat("No feasible solution found. Try adjusting the requirements.")
      })
    }
  })
}

shinyApp(ui, server)
