# =============================================================================
# formulation.R
#
# Shared building blocks for the three formulation tabs (Simplified, Full,
# Import). Each tab shows the same layout:
#
#   sidebar: [tab-specific controls] + nutrient targets + action buttons
#   main:    [tab-specific content] + available ingredients table
#            + selected ingredients table (only the cost column is editable)
#            + solution
#
# The tabs differ only in where the "available ingredients" come from. Each
# tab module therefore calls formulation_ui() in its UI function and
# setup_formulation() inside its moduleServer(), passing in a reactive that
# returns its ingredient table.
# =============================================================================


#' UI of a formulation tab
#'
#' @param id module id (must be the same id that is passed to moduleServer()
#'   of the tab, so that setup_formulation() finds the inputs).
#' @param sidebar_top optional UI placed at the top of the sidebar.
#' @param main_top optional UI placed at the top of the main panel.
formulation_ui <- function(id, sidebar_top = NULL, main_top = NULL) {
  ns <- NS(id)

  fluidPage(
    sidebarLayout(
      sidebarPanel(
        sidebar_top,

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
        main_top,

        h3("Available Ingredients"),
        helpText("Click on rows to add ingredients to the selection."),
        DTOutput(ns("feed_table")),

        h3("Selected Ingredients"),
        helpText(
          "Nutrient values are fixed. Double-click a cell in the cost column,",
          "enter the price per kg and click outside the cell (or press Tab)",
          "to save it. Costs are required for least-cost formulation."
        ),
        DTOutput(ns("selected_feed_table")),

        h3("Solution"),
        verbatimTextOutput(ns("solution_text"))
      )
    )
  )
}


#' Server logic of a formulation tab
#'
#' Must be called from inside moduleServer() of a tab module, passing that
#' module's `input`, `output` and `session`.
#'
#' @param input,output,session the module's Shiny objects.
#' @param available_data reactive returning the table of ingredients the user
#'   can choose from (columns `label_col`, NUTRIENTS, optionally `cost`), or
#'   NULL if there is nothing to show yet.
#' @param label_col name of the column that identifies an ingredient.
#' @param label_title column header used for `label_col`.
#' @param empty_message message shown when `available_data()` is empty.
#' @return a list with
#'   * `clear()`: function that empties the selection and the solution
#'     (e.g. when the underlying data is replaced),
#'   * `selection`: reactive returning the current selection (or NULL).
setup_formulation <- function(input, output, session, available_data,
                              label_col = "ingredient",
                              label_title = "Ingredient",
                              empty_message = "No ingredients available.") {

  # State ----
  # Ingredients selected by the user (persists across filter changes) and the
  # most recent formulation result or message.
  selected_ingredients <- reactiveVal(NULL)
  solution <- reactiveVal(NULL)
  # Incremented whenever the selected-ingredients table must be re-drawn
  # (rows added/removed, invalid edit reverted). Valid cost edits are already
  # shown by the browser, so they do not re-render the table; this keeps
  # paging/sorting and lets the user move straight to the next cost cell.
  selection_version <- reactiveVal(0)

  feed_proxy <- dataTableProxy("feed_table")

  clear <- function() {
    selected_ingredients(NULL)
    selection_version(selection_version() + 1)
    solution(NULL)
    selectRows(feed_proxy, NULL)
  }


  # Available ingredients ----
  output$feed_table <- renderDT({
    data <- available_data()
    validate(need(!is.null(data) && nrow(data) > 0, empty_message))

    display_cols <- intersect(c(label_col, NUTRIENTS, "cost"), names(data))
    datatable(
      data[, display_cols, drop = FALSE],
      rownames = FALSE,
      selection = "multiple",
      colnames = column_titles(display_cols, label_col, label_title),
      options = list(pageLength = 10, autoWidth = TRUE)
    ) %>%
      formatRound(which(display_cols %in% NUTRIENTS), digits = 2)
  })

  # Add newly clicked rows to the persistent selection
  observeEvent(input$feed_table_rows_selected, {
    picked <- available_data()[input$feed_table_rows_selected, , drop = FALSE]
    selected_ingredients(
      add_to_selection(selected_ingredients(), picked, label_col)
    )
    selection_version(selection_version() + 1)
  })

  observeEvent(input$clear_selection, clear())


  # Selected ingredients (only the cost column is editable) ----
  output$selected_feed_table <- renderDT({
    selection_version()
    selection <- isolate(selected_ingredients())
    if (is.null(selection) || nrow(selection) == 0) {
      return(datatable(data.frame(Message = "No ingredients selected"),
                       rownames = FALSE, options = list(dom = "t")))
    }

    # DT column indices are 0-based (no row names shown); lock all but cost
    cost_index <- which(names(selection) == "cost") - 1
    locked_columns <- setdiff(seq_along(selection) - 1, cost_index)

    datatable(
      selection,
      rownames = FALSE,
      selection = "none",
      colnames = column_titles(names(selection), label_col, label_title),
      editable = list(target = "cell", disable = list(columns = locked_columns)),
      options = list(dom = "tip", pageLength = 25)
    ) %>%
      formatRound(which(names(selection) %in% NUTRIENTS), digits = 2)
  }, server = FALSE)  # client-side: edited cells are updated in the browser

  observeEvent(input$selected_feed_table_cell_edit, {
    edit <- input$selected_feed_table_cell_edit
    selection <- selected_ingredients()
    column <- names(selection)[edit$col + 1]

    # Defensive check: only the cost column may be changed
    if (!identical(column, "cost")) {
      selection_version(selection_version() + 1)  # restore original values
      return()
    }

    raw <- str_trim(as.character(edit$value))
    value <- parse_decimal(raw)

    if (raw != "" && (is.na(value) || value < 0)) {
      showNotification("Cost must be a non-negative number.", type = "error")
      selection_version(selection_version() + 1)  # restore previous value
      return()
    }

    selection$cost[edit$row] <- value  # empty input -> NA (cost not entered)
    selected_ingredients(selection)
  })


  # Formulation ----
  observeEvent(input$formulate, {
    selection <- selected_ingredients()
    targets <- c(
      protein      = input$protein_req,
      lipid        = input$fat_req,
      carbohydrate = input$carbohydrate_req,
      ash          = input$ash_req,
      energy       = input$energy_req
    )

    if (is.null(selection) || nrow(selection) == 0) {
      solution("Please select at least one ingredient.")
    } else if (any(is.na(targets))) {
      solution("Please enter a value for every nutrient target.")
    } else if (input$least_cost && any(is.na(selection$cost))) {
      missing <- selection[[label_col]][is.na(selection$cost)]
      solution(c(
        "Least-cost formulation selected, but cost data is missing for:",
        paste0("  - ", missing),
        "",
        "Please enter cost values in the Selected Ingredients table."
      ))
    } else {
      result <- formulate_feed(selection, targets, input$least_cost, label_col)
      solution(format_solution(result))
    }
  })

  output$solution_text <- renderPrint({
    req(solution())
    cat(solution(), sep = "\n")
  })

  list(clear = clear, selection = reactive(selected_ingredients()))
}


#' Column headers for the ingredient tables
#'
#' @param cols column names of the table.
#' @param label_col name of the label column; its header is `label_title`.
#' @return character vector of display names.
column_titles <- function(cols, label_col, label_title) {
  titles <- c(NUTRIENT_LABELS, cost = "Cost (per kg)", category1 = "Category")
  titles[label_col] <- label_title
  unname(ifelse(cols %in% names(titles), titles[cols], cols))
}
