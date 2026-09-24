# =============================================================================
# server_full.R - server logic of the "Full" tab
#
# Offers all ingredients of feed_data (see code/data_prep.R), optionally
# filtered by category. The selection persists when the filter is changed,
# so ingredients from several categories can be combined. All table,
# selection and formulation logic lives in setup_formulation()
# (code/modules/formulation.R).
# =============================================================================

#' @param id module id; must match the id passed to ui_full().
server_full <- function(id) {
  moduleServer(id, function(input, output, session) {

    # Ingredient table filtered by the selected category
    filtered_data <- reactive({
      req(input$category_filter)

      if (input$category_filter == "All") {
        feed_data
      } else {
        feed_data[feed_data$category1 %in% input$category_filter, ]
      }
    })

    observeEvent(input$category_filter, {
      log_info(id, "Category filter set to '", input$category_filter, "' (",
               nrow(filtered_data()), " ingredients shown)")
    })

    setup_formulation(
      input, output, session,
      available_data = filtered_data,
      label_col = "ingredient",
      label_title = "Ingredient",
      show_selected_nutrients = FALSE  # already shown in the available table
    )
  })
}
