# =============================================================================
# server_summary.R - server logic of the "Simplified" tab
#
# Offers the ingredient categories of feed_data_summarised (see
# code/data_prep.R). All table, selection and formulation logic lives in
# setup_formulation() (code/modules/formulation.R).
# =============================================================================

#' @param id module id; must match the id passed to ui_summary().
server_summary <- function(id) {
  moduleServer(id, function(input, output, session) {
    setup_formulation(
      input, output, session,
      available_data = reactive(feed_data_summarised),
      label_col = "category1",
      label_title = "Category",
      show_selected_nutrients = FALSE,  # already shown in the available table
      tab_title = "Simplified",
      data_source = paste("Category means of", basename(FEED_DATA_FILE))
    )
  })
}
