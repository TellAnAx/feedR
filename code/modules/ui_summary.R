ui_summary <- function(id) {
  ns <- NS(id)

  fluidPage(

    sidebarLayout(
      sidebarPanel(

        wellPanel(
          h4("Targeted Nutrient Composition"),
          numericInput(ns("protein_req"), "Protein (%)", value = 20, min = 0, max = 100),
          numericInput(ns("fat_req"), "Fat (%)", value = 5, min = 0, max = 100),
          numericInput(ns("carbohydrate_req"), "Carbohydrate (%)", value = 8, min = 0, max = 100),
          numericInput(ns("ash_req"), "Ash (%)", value = 6, min = 0, max = 100),
          tags$br(),
          numericInput(ns("energy_req"), "Energy (MJ/kg)", value = 12, min = 0, max = 100),
          tags$br(),
          checkboxInput(ns("least_cost"), "Perform Least-Cost Formulation", value = FALSE),
          actionButton(ns("formulate"), "Formulate"),
          actionButton(ns("clear_selection"), "Clear Selection")

        )
      ),

      mainPanel(
        h3("Available Ingredients"),
        DTOutput(ns("feed_table")),

        h3("Selected Ingredients"),
        DTOutput(ns("selected_feed_table")),

        h3("Solution"),
        verbatimTextOutput(ns("solution_text"))
      )
    )
  )
}
