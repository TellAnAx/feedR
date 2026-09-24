# =============================================================================
# ui_summary.R - UI of the "Simplified" tab
#
# The simplified tab formulates with ingredient *categories* (fish, plant,
# oil, ...) whose nutrient values are the category means computed in
# code/data_prep.R (feed_data_summarised).
# =============================================================================

#' @param id module id; must match the id passed to server_summary().
ui_summary <- function(id) {
  formulation_ui(id)
}
