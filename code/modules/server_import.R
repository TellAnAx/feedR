# =============================================================================
# server_import.R - server logic of the "Import" tab
#
# Reads the uploaded CSV with read_ingredient_csv() (code/helper_functions.R)
# and uses it as the table of available ingredients. All table, selection and
# formulation logic lives in setup_formulation() (code/modules/formulation.R).
# =============================================================================

#' @param id module id; must match the id passed to ui_import().
server_import <- function(id) {
  moduleServer(id, function(input, output, session) {

    # Result of reading the uploaded file: list(data = <data.frame>) on
    # success or list(error = <message>) if the file is invalid.
    imported <- reactive({
      req(input$file)
      tryCatch(
        list(data = read_ingredient_csv(input$file$datapath)),
        error = function(e) list(error = conditionMessage(e))
      )
    })

    imported_data <- reactive({
      if (is.null(input$file)) return(NULL)
      imported()$data
    })

    output$import_status <- renderUI({
      if (is.null(input$file)) return(NULL)
      result <- imported()
      if (!is.null(result$error)) {
        div(class = "alert alert-danger",
            tags$b("Could not import ", input$file$name, ": "), result$error)
      } else {
        div(class = "alert alert-success",
            "Imported ", nrow(result$data), " ingredients from ",
            tags$b(input$file$name), ".")
      }
    })

    # Template: a static example file (data/templates/) in the expected
    # format, with an empty cost column to fill in.
    output$template <- downloadHandler(
      filename = "feedR_ingredients_template.csv",
      content = function(file) file.copy(INGREDIENT_TEMPLATE, file),
      contentType = "text/csv"
    )

    formulation <- setup_formulation(
      input, output, session,
      available_data = imported_data,
      label_col = "ingredient",
      label_title = "Ingredient",
      empty_message = "Upload a CSV file to see your ingredients here."
    )

    # A new file replaces the ingredient list, so the old selection is void
    observeEvent(input$file, formulation$clear())
  })
}
