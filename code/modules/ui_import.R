# =============================================================================
# ui_import.R - UI of the "Import" tab
#
# Lets the user upload their own ingredient table as a CSV file (same format
# as the "Available Ingredients" table, see read_ingredient_csv() in
# code/helper_functions.R) and formulate with it.
# =============================================================================

#' @param id module id; must match the id passed to server_import().
ui_import <- function(id) {
  ns <- NS(id)

  formulation_ui(
    id,
    sidebar_top = wellPanel(
      h4("Import Ingredients"),
      fileInput(ns("file"), "Upload CSV file",
                accept = c(".csv", "text/csv", "text/comma-separated-values")),
      helpText(
        "Required columns: ingredient, protein, lipid, carbohydrate, ash",
        "(all in % of the ingredient) and energy (MJ/kg).",
        "Optional columns: cost (per kg) and category.",
        "Comma- or semicolon-separated files are accepted."
      ),
      downloadButton(ns("template"), "Download CSV template",
                     class = "btn-sm")
    ),
    main_top = uiOutput(ns("import_status"))
  )
}
