# =============================================================================
# ui_manual.R - UI of the "Manual" tab
#
# Everything is entered by hand, in two steps:
#   1. define the composition parts (nutrients) to formulate for, each with
#      a target value,
#   2. add the available ingredients row by row with their content of every
#      composition part (and optionally a cost).
# All entered ingredients are automatically used in the formulation.
# =============================================================================

#' @param id module id; must match the id passed to server_manual().
ui_manual <- function(id) {
  ns <- NS(id)

  fluidPage(
    sidebarLayout(
      sidebarPanel(

        wellPanel(
          h4("1. Composition Parts"),
          helpText(
            "Define the composition parts to formulate for and their target",
            "values in the mix, e.g. \"Protein (%)\" with target 40."
          ),
          textInput(ns("part_name"), "Name", placeholder = "e.g. Protein (%)"),
          fluidRow(
            column(7, numericInput(ns("part_target"), "Target in the mix", value = NA)),
            column(5, numericInput(ns("part_max"), "Maximum", value = NA))
          ),
          helpText(
            "Maximum is optional. If it is set, the target becomes a minimum",
            "and the mix must lie between the two values."
          ),
          actionButton(ns("add_part"), "Add Composition Part", icon = icon("plus")),
          tags$br(), tags$br(),
          actionButton(ns("load_standard"), "Add Standard Nutrients",
                       class = "btn-sm"),
          helpText("Adds protein, lipid, carbohydrate, ash and energy.")
        ),

        wellPanel(
          h4("2. Add Ingredient"),
          textInput(ns("ingredient_name"), "Ingredient name",
                    placeholder = "e.g. Fish meal"),
          uiOutput(ns("ingredient_values")),
          numericInput(ns("ingredient_cost"), "Cost per kg (optional)",
                       value = NA, min = 0),
          actionButton(ns("add_ingredient"), "Add Ingredient", icon = icon("plus"))
        ),

        wellPanel(
          h4("3. Formulate"),
          checkboxInput(ns("least_cost"), "Perform Least-Cost Formulation", value = FALSE),
          actionButton(ns("formulate"), "Formulate"),
          actionButton(ns("clear_all"), "Start Over")
        )
      ),

      mainPanel(
        h3("Composition Parts"),
        helpText(
          "Double-click a target or maximum to change it (clear the maximum",
          "to remove it). Click rows to select them for removal."
        ),
        DTOutput(ns("parts_table")),
        actionButton(ns("remove_parts"), "Remove Selected Parts", class = "btn-sm"),

        h3("Ingredients"),
        helpText(
          "All ingredients listed here are used in the formulation.",
          "Double-click a value to correct it, then click outside the cell",
          "(or press Tab) to save. Click rows to select them for removal."
        ),
        DTOutput(ns("ingredients_table")),
        actionButton(ns("remove_ingredients"), "Remove Selected Ingredients",
                     class = "btn-sm"),

        h3("Solution"),
        verbatimTextOutput(ns("solution_text"))
      )
    )
  )
}
