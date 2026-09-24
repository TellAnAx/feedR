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
          helpText(
            "Maximum is optional. If it is set, the target becomes a",
            "minimum and the mix must lie between the two values."
          ),
          target_input_row(ns, "protein", "Protein (%)", 20),
          target_input_row(ns, "lipid", "Fat (%)", 5),
          target_input_row(ns, "carbohydrate", "Carbohydrate (%)", 8),
          target_input_row(ns, "ash", "Ash (%)", 6),
          target_input_row(ns, "energy", "Energy (MJ/kg)", 12),
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


#' Input-id prefixes of the target inputs per nutrient. The target input is
#' "<prefix>_req", the optional maximum "<prefix>_max".
TARGET_INPUT_PREFIX <- c(protein = "protein", lipid = "fat",
                         carbohydrate = "carbohydrate", ash = "ash",
                         energy = "energy")


#' One row of the target sidebar: target (or minimum) and optional maximum
#'
#' @param ns namespace function of the module.
#' @param nutrient one of NUTRIENTS.
#' @param label label of the target input.
#' @param value default target.
target_input_row <- function(ns, nutrient, label, value) {
  prefix <- TARGET_INPUT_PREFIX[[nutrient]]
  fluidRow(
    column(7, numericInput(ns(paste0(prefix, "_req")), label, value = value, min = 0)),
    column(5, numericInput(ns(paste0(prefix, "_max")), "Maximum", value = NA, min = 0))
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

  # Module id (e.g. "full"), used to tag log messages
  log_ctx <- sub("-$", "", session$ns(""))
  log_debug(log_ctx, "Formulation tab initialised (ingredient column: ", label_col, ")")

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
    log_info(log_ctx, "Selection and solution cleared")
    selected_ingredients(NULL)
    selection_version(selection_version() + 1)
    solution(NULL)
    selectRows(feed_proxy, NULL)
  }


  # Available ingredients ----
  output$feed_table <- renderDT({
    data <- available_data()
    validate(need(!is.null(data) && nrow(data) > 0, empty_message))
    log_debug(log_ctx, "Rendering available ingredients table (", nrow(data), " rows)")

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
    before <- selected_ingredients()
    after <- add_to_selection(before, picked, label_col)
    added <- setdiff(after[[label_col]], before[[label_col]])
    if (length(added) > 0) {
      log_info(log_ctx, "Added to selection: ", paste(added, collapse = "; "),
               " (now ", nrow(after), " selected)")
    }
    selected_ingredients(after)
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
    ingredient <- selection[[label_col]][edit$row]

    # Defensive check: only the cost column may be changed
    if (!identical(column, "cost")) {
      log_warn(log_ctx, "Rejected edit of locked column '", column, "' for ", ingredient)
      selection_version(selection_version() + 1)  # restore original values
      return()
    }

    raw <- str_trim(as.character(edit$value))
    value <- parse_decimal(raw)

    if (raw != "" && (is.na(value) || value < 0)) {
      log_warn(log_ctx, "Rejected invalid cost '", raw, "' for ", ingredient)
      showNotification("Cost must be a non-negative number.", type = "error")
      selection_version(selection_version() + 1)  # restore previous value
      return()
    }

    log_info(log_ctx, "Cost of ", ingredient, " set to ", fmt_num(value))
    selection$cost[edit$row] <- value  # empty input -> NA (cost not entered)
    selected_ingredients(selection)
  })


  # Formulation ----
  observeEvent(input$formulate, {
    selection <- selected_ingredients()
    read_inputs <- function(suffix) {
      map_dbl(TARGET_INPUT_PREFIX[NUTRIENTS], function(prefix) {
        value <- input[[paste0(prefix, suffix)]]
        if (is.null(value)) NA_real_ else value
      }) %>% set_names(NUTRIENTS)
    }
    targets <- read_inputs("_req")
    maxima <- read_inputs("_max")

    log_info(log_ctx, "Formulate clicked: ", NROW(selection), " ingredients, ",
             if (isTRUE(input$least_cost)) "least-cost" else "target matching")
    log_debug(log_ctx, "Targets/minima: ", fmt_num(targets), " | maxima: ", fmt_num(maxima))

    bound_problems <- check_bounds(targets, maxima, NUTRIENT_LABELS[NUTRIENTS])

    if (is.null(selection) || nrow(selection) == 0) {
      solution("Please select at least one ingredient.")
    } else if (length(bound_problems) > 0) {
      solution(c("Please check the nutrient targets:", paste0("  - ", bound_problems)))
    } else if (input$least_cost && any(is.na(selection$cost))) {
      missing <- selection[[label_col]][is.na(selection$cost)]
      solution(c(
        "Least-cost formulation selected, but cost data is missing for:",
        paste0("  - ", missing),
        "",
        "Please enter cost values in the Selected Ingredients table."
      ))
    } else {
      result <- formulate_feed(selection, targets, maxima,
                               least_cost = input$least_cost,
                               label_col = label_col,
                               log_context = log_ctx)
      solution(format_solution(result))
      return()
    }
    log_warn(log_ctx, "Formulation not started: ", solution()[1])
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
