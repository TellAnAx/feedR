# =============================================================================
# server_manual.R - server logic of the "Manual" tab
#
# State:
#   parts       - data.frame(key, name, target): the composition parts defined
#                 by the user. `key` is an internal, input-id-safe column name
#                 ("part1", "part2", ...); `name` is what the user typed.
#   ingredients - data.frame with columns ingredient, one column per part key
#                 and cost. Every row is used in the formulation.
#
# The formulation itself is done by formulate_feed() and format_solution()
# (code/helper_functions.R), called with the user's parts as `nutrients`.
# =============================================================================

#' @param id module id; must match the id passed to ui_manual().
server_manual <- function(id) {
  moduleServer(id, function(input, output, session) {

    # State ----
    empty_parts <- data.frame(key = character(), name = character(),
                              target = numeric())
    empty_ingredients <- data.frame(ingredient = character(), cost = numeric())

    parts <- reactiveVal(empty_parts)
    ingredients <- reactiveVal(empty_ingredients)
    solution <- reactiveVal(NULL)
    next_key <- reactiveVal(1)  # counter for unique part keys

    # The tables are only re-rendered when these counters change (rows or
    # columns added/removed, invalid edit reverted). Valid cell edits are
    # already shown by the browser, so the user can keep editing without the
    # table being redrawn.
    parts_version <- reactiveVal(0)
    ingredients_version <- reactiveVal(0)
    bump <- function(version) version(version() + 1)

    notify_error <- function(...) showNotification(paste0(...), type = "error")


    # Step 1: composition parts ----

    # Adds a composition part; returns FALSE (with a notification) if invalid
    add_part <- function(name, target) {
      name <- str_trim(name)
      if (name == "") {
        notify_error("Please enter a name for the composition part.")
        return(FALSE)
      }
      if (tolower(name) %in% tolower(parts()$name)) {
        notify_error("A composition part named '", name, "' already exists.")
        return(FALSE)
      }
      if (is.null(target) || is.na(target)) {
        notify_error("Please enter a target value for '", name, "'.")
        return(FALSE)
      }

      key <- paste0("part", next_key())
      next_key(next_key() + 1)
      parts(rbind(parts(), data.frame(key = key, name = name, target = target)))

      # Existing ingredients get an empty value for the new part, to be
      # filled in by editing the ingredients table
      current <- ingredients()
      current[[key]] <- rep(NA_real_, nrow(current))
      ingredients(current[, c("ingredient", parts()$key, "cost")])

      bump(parts_version)
      bump(ingredients_version)
      TRUE
    }

    observeEvent(input$add_part, {
      if (add_part(input$part_name, input$part_target)) {
        updateTextInput(session, "part_name", value = "")
      }
    })

    observeEvent(input$load_standard, {
      defaults <- c(protein = 20, lipid = 5, carbohydrate = 8, ash = 6, energy = 12)
      for (nutrient in NUTRIENTS) {
        name <- NUTRIENT_LABELS[[nutrient]]
        if (!tolower(name) %in% tolower(parts()$name)) {
          add_part(name, defaults[[nutrient]])
        }
      }
    })

    output$parts_table <- renderDT({
      parts_version()
      current <- isolate(parts())

      datatable(
        current[, c("name", "target")],
        rownames = FALSE,
        colnames = c("Composition part", "Target"),
        selection = "multiple",
        editable = list(target = "cell", disable = list(columns = 0)),
        options = list(dom = "t", pageLength = -1,
                       language = list(emptyTable = "No composition parts defined yet."))
      )
    }, server = FALSE)

    observeEvent(input$parts_table_cell_edit, {
      edit <- input$parts_table_cell_edit
      value <- parse_decimal(edit$value)
      current <- parts()

      if (edit$col != 1 || is.na(value)) {
        if (edit$col == 1) notify_error("The target must be a number.")
        bump(parts_version)  # restore previous value
        return()
      }
      current$target[edit$row] <- value
      parts(current)
    })

    observeEvent(input$remove_parts, {
      rows <- input$parts_table_rows_selected
      if (length(rows) == 0) {
        notify_error("Click on composition parts in the table to select them first.")
        return()
      }
      removed_keys <- parts()$key[rows]
      parts(parts()[-rows, , drop = FALSE])
      current <- ingredients()
      ingredients(current[, setdiff(names(current), removed_keys), drop = FALSE])
      bump(parts_version)
      bump(ingredients_version)
    })


    # Step 2: ingredients ----

    # One numeric input per composition part. Only re-rendered when parts are
    # added or removed (not when a target is edited), so typed values survive.
    output$ingredient_values <- renderUI({
      parts_version()
      current <- isolate(parts())
      if (nrow(current) == 0) {
        return(helpText("Define composition parts first (step 1)."))
      }
      map2(current$key, current$name, function(key, name) {
        numericInput(session$ns(paste0("value_", key)), name, value = NA)
      })
    })

    observeEvent(input$add_ingredient, {
      current_parts <- parts()
      name <- str_trim(input$ingredient_name)
      values <- map_dbl(current_parts$key, function(key) {
        value <- input[[paste0("value_", key)]]
        if (is.null(value)) NA_real_ else value
      })
      cost <- input$ingredient_cost
      if (is.null(cost)) cost <- NA_real_

      if (nrow(current_parts) == 0) {
        return(notify_error("Please define at least one composition part first."))
      }
      if (name == "") {
        return(notify_error("Please enter an ingredient name."))
      }
      if (tolower(name) %in% tolower(ingredients()$ingredient)) {
        return(notify_error("An ingredient named '", name, "' already exists."))
      }
      if (any(is.na(values))) {
        return(notify_error("Please enter a value for: ",
                            paste(current_parts$name[is.na(values)], collapse = ", "), "."))
      }
      if (!is.na(cost) && cost < 0) {
        return(notify_error("The cost must not be negative."))
      }

      new_row <- data.frame(ingredient = name, as.list(set_names(values, current_parts$key)),
                            cost = cost)
      ingredients(rbind(ingredients(), new_row))
      bump(ingredients_version)

      updateTextInput(session, "ingredient_name", value = "")
    })

    output$ingredients_table <- renderDT({
      ingredients_version()
      current <- isolate(ingredients())
      current_parts <- isolate(parts())

      datatable(
        current,
        rownames = FALSE,
        colnames = c("Ingredient", current_parts$name, "Cost (per kg)"),
        selection = "multiple",
        editable = list(target = "cell", disable = list(columns = 0)),
        options = list(dom = "tip", pageLength = 25,
                       language = list(emptyTable = "No ingredients added yet."))
      )
    }, server = FALSE)

    observeEvent(input$ingredients_table_cell_edit, {
      edit <- input$ingredients_table_cell_edit
      current <- ingredients()
      column <- names(current)[edit$col + 1]
      raw <- str_trim(as.character(edit$value))
      value <- parse_decimal(raw)

      valid <- column != "ingredient" &&
        (raw == "" || !is.na(value)) &&
        !(column == "cost" && !is.na(value) && value < 0)
      if (!valid) {
        notify_error(if (column == "cost") {
          "Cost must be empty or a non-negative number."
        } else {
          "Please enter a number."
        })
        bump(ingredients_version)  # restore previous value
        return()
      }

      current[[column]][edit$row] <- value  # empty input -> NA
      ingredients(current)
    })

    observeEvent(input$remove_ingredients, {
      rows <- input$ingredients_table_rows_selected
      if (length(rows) == 0) {
        notify_error("Click on ingredients in the table to select them first.")
        return()
      }
      ingredients(ingredients()[-rows, , drop = FALSE])
      bump(ingredients_version)
    })


    # Step 3: formulation ----
    observeEvent(input$formulate, {
      current_parts <- parts()
      current <- ingredients()
      values <- as.matrix(current[, current_parts$key, drop = FALSE])

      if (nrow(current_parts) == 0) {
        solution("Please define at least one composition part (step 1).")
      } else if (nrow(current) == 0) {
        solution("Please add at least one ingredient (step 2).")
      } else if (anyNA(values)) {
        missing <- current$ingredient[rowSums(is.na(values)) > 0]
        solution(c(
          "Some composition values are missing for:",
          paste0("  - ", missing),
          "",
          "Please fill them in by double-clicking the cells in the Ingredients table."
        ))
      } else if (input$least_cost && anyNA(current$cost)) {
        solution(c(
          "Least-cost formulation selected, but cost data is missing for:",
          paste0("  - ", current$ingredient[is.na(current$cost)]),
          "",
          "Please enter cost values in the Ingredients table."
        ))
      } else {
        result <- formulate_feed(
          current,
          targets = set_names(current_parts$target, current_parts$key),
          least_cost = input$least_cost,
          label_col = "ingredient",
          nutrients = current_parts$key,
          nutrient_labels = current_parts$name
        )
        solution(format_solution(result))
      }
    })

    output$solution_text <- renderPrint({
      req(solution())
      cat(solution(), sep = "\n")
    })

    observeEvent(input$clear_all, {
      parts(empty_parts)
      ingredients(empty_ingredients)
      solution(NULL)
      bump(parts_version)
      bump(ingredients_version)
    })
  })
}
