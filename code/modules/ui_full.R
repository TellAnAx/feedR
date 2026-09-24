# =============================================================================
# ui_full.R - UI of the "Full" tab
#
# The full tab formulates with the individual ingredients of the feed
# ingredient database (feed_data, see code/data_prep.R). In addition to the
# shared formulation layout it has a category filter for the ingredient table.
# =============================================================================

#' @param id module id; must match the id passed to server_full().
ui_full <- function(id) {
  ns <- NS(id)

  formulation_ui(
    id,
    sidebar_top = wellPanel(
      h4("Ingredient Filters & Options"),
      selectInput(ns("category_filter"), "Filter by Category:",
                  choices = c("All", sort(unique(na.omit(feed_data$category1)))),
                  selected = "All")
    )
  )
}
