# =============================================================================
# helper_functions.R
#
# Pure (non-reactive) helper functions shared by all tabs of the app:
#   * constants describing the nutrients used in the formulation
#   * building / updating the table of selected ingredients
#   * the linear-programming formulation itself (formulate_feed())
#   * formatting of the solution for display
#   * reading and validating user-supplied ingredient CSV files
#
# Keeping these functions free of Shiny code makes them easy to test from the
# R console, e.g.
#   formulate_feed(feed_data_summarised[c(3, 6, 7), ],
#                  targets = c(protein = 40, lipid = 10, carbohydrate = 25,
#                              ash = 8, energy = 18),
#                  label_col = "category1")
# =============================================================================


# Constants -------------------------------------------------------------------

#' Nutrient columns used in the formulation (in this order).
#' Every ingredient table (built-in or imported) must contain these columns.
NUTRIENTS <- c("protein", "lipid", "carbohydrate", "ash", "energy")

#' Human-readable column headers for the nutrient columns.
NUTRIENT_LABELS <- c(
  protein      = "Protein (%)",
  lipid        = "Lipid (%)",
  carbohydrate = "Carbohydrate (%)",
  ash          = "Ash (%)",
  energy       = "Energy (MJ/kg)"
)


#' Example ingredient CSV offered as a download template (Import tab).
#' It uses the format expected by read_ingredient_csv().
INGREDIENT_TEMPLATE <- "data/templates/ingredients_template.csv"


# Parsing ---------------------------------------------------------------------

#' Parse user-entered text as numbers
#'
#' Accepts both "." and "," as decimal separator (e.g. "2.5" and "2,5").
#'
#' @param x character (or numeric) vector.
#' @return numeric vector; NA where the input is empty or not a number.
parse_decimal <- function(x) {
  suppressWarnings(as.numeric(str_replace(str_trim(as.character(x)), ",", ".")))
}


# Selection handling ----------------------------------------------------------

#' Add ingredients to the persistent selection
#'
#' Rows of `picked` whose label is not yet part of `selection` are appended.
#' Ingredients that are already selected are left untouched, so cost values
#' the user has entered are preserved.
#'
#' @param selection data.frame with the current selection (columns
#'   `label_col`, NUTRIENTS, `cost`), or NULL if nothing is selected yet.
#' @param picked data.frame of ingredients to add (rows of an ingredient table).
#'   If it contains a `cost` column, those values are used as initial costs;
#'   otherwise the cost starts out as NA (= not yet entered).
#' @param label_col name of the column that identifies an ingredient
#'   (e.g. "ingredient" or "category1").
#' @return data.frame with columns `label_col`, NUTRIENTS and `cost`.
add_to_selection <- function(selection, picked, label_col) {
  new <- as.data.frame(picked)
  if (!is.null(selection)) {
    new <- new[!new[[label_col]] %in% selection[[label_col]], , drop = FALSE]
  }

  new_rows <- new[, c(label_col, NUTRIENTS), drop = FALSE]
  new_rows$cost <- if ("cost" %in% names(new)) {
    as.numeric(new$cost)
  } else {
    rep(NA_real_, nrow(new))
  }

  combined <- if (is.null(selection)) new_rows else rbind(selection, new_rows)
  rownames(combined) <- NULL
  combined
}


# Formulation -----------------------------------------------------------------

#' Check targets and optional maxima before formulating
#'
#' @param targets named numeric vector of targets (minima where a maximum is
#'   set).
#' @param maxima named numeric vector of maxima, NA = no maximum.
#' @param labels display names of the nutrients (same order).
#' @return character vector of problems (empty if everything is fine).
check_bounds <- function(targets, maxima, labels) {
  problems <- character()
  if (anyNA(targets)) {
    problems <- c(problems, paste0(
      "Please enter a target for: ", paste(labels[is.na(targets)], collapse = ", "), "."
    ))
  }
  bad <- !is.na(targets) & !is.na(maxima) & maxima < targets
  if (any(bad)) {
    problems <- c(problems, sprintf(
      "%s: the maximum (%s) is smaller than the minimum (%s).",
      labels[bad], fmt_num(maxima[bad]), fmt_num(targets[bad])
    ))
  }
  problems
}


#' Formulate a feed mix with linear programming
#'
#' The decision variables are the inclusion rates x_i of the selected
#' ingredients, expressed as fractions of the final mix (x_i >= 0,
#' sum(x_i) = 1). The nutrient content of the mix is the inclusion-weighted
#' average of the ingredient nutrient contents, which is linear in x.
#'
#' Every nutrient j has a target t_j and optionally a maximum u_j. If a
#' maximum is set, the target is treated as a minimum and the nutrient must
#' lie in the range t_j <= sum_i a_ij x_i <= u_j (a hard constraint).
#'
#' Two models are available (see also the FAQ tab):
#'
#' * Target matching (`least_cost = FALSE`, goal programming):
#'     minimise   sum_j (under_j + over_j)          over nutrients without max
#'     subject to sum_i a_ij x_i + under_j - over_j = t_j   (no max)
#'                t_j <= sum_i a_ij x_i <= u_j             (with max)
#'                sum_i x_i = 1
#'                x, under, over >= 0
#'   i.e. the mix that meets all ranges and deviates least (in absolute
#'   units) from the remaining targets.
#'
#' * Least cost (`least_cost = TRUE`):
#'     minimise   sum_i c_i x_i
#'     subject to sum_i a_ij x_i >= t_j                     (no max)
#'                t_j <= sum_i a_ij x_i <= u_j             (with max)
#'                sum_i x_i = 1
#'                x >= 0
#'   i.e. the cheapest mix that meets every minimum and every range.
#'
#' If no mix satisfies the hard constraints, the result has
#' `feasible = FALSE` and `diagnosis` explains which constraints conflict
#' (see diagnose_infeasibility()). Solver errors are caught and returned the
#' same way, so this function does not fail on bad input combinations.
#'
#' @param ingredients data.frame with columns `label_col`, `nutrients` and
#'   (for least-cost formulation) `cost`.
#' @param targets named numeric vector of targets, names = `nutrients`.
#' @param maxima named numeric vector of optional maxima, names = `nutrients`,
#'   NA = no maximum. NULL means no maxima at all.
#' @param least_cost logical; use the least-cost model instead of target
#'   matching.
#' @param label_col name of the column identifying the ingredients.
#' @param nutrients names of the nutrient (composition part) columns to
#'   formulate for. Defaults to the built-in NUTRIENTS; the "Manual" tab
#'   passes the composition parts defined by the user.
#' @param nutrient_labels display names of `nutrients` (used in the output).
#' @param log_context tag used in log messages (e.g. the module id).
#' @return A list with elements
#'   * `feasible`: TRUE if the solver found an optimal solution,
#'   * `mode`: "least_cost" or "target_matching",
#'   * `inclusion`: named vector of inclusion fractions (sums to 1),
#'   * `targets`, `maxima`, `achieved`: named nutrient vectors,
#'   * `labels`: display names of the nutrients,
#'   * `total_cost`: cost of 1 kg of the mix (NA if costs are missing),
#'   * `objective`: value of the objective function,
#'   * `status`: raw lpSolve status code (0 = optimal, 2 = infeasible, ...),
#'   * `diagnosis`: character vector explaining an infeasible result.
formulate_feed <- function(ingredients, targets, maxima = NULL,
                           least_cost = FALSE,
                           label_col = "ingredient",
                           nutrients = NUTRIENTS,
                           nutrient_labels = NUTRIENT_LABELS[nutrients],
                           log_context = "lp") {
  targets <- targets[nutrients]
  maxima <- if (is.null(maxima)) {
    set_names(rep(NA_real_, length(nutrients)), nutrients)
  } else {
    maxima[nutrients]
  }
  nutrient_labels <- unname(nutrient_labels)
  ranged <- !is.na(maxima)  # nutrients with a min-max range

  n_ing <- nrow(ingredients)
  n_nut <- length(nutrients)
  mode <- if (least_cost) "least_cost" else "target_matching"

  log_info(log_context, "Building LP (", mode, "): ", n_ing, " ingredients, ",
           n_nut, " nutrients, ", sum(ranged), " with min-max range")

  # Nutrient matrix A: one row per nutrient, one column per ingredient
  A <- t(as.matrix(ingredients[, nutrients, drop = FALSE]))
  dimnames(A) <- list(nutrient_labels, ingredients[[label_col]])
  log_object(log_context, "Nutrient matrix A (nutrients x ingredients):", A)

  # Hard constraints shared by both models: ranges and mass balance
  range_con <- rbind(A[ranged, , drop = FALSE], A[ranged, , drop = FALSE])
  range_dir <- c(rep(">=", sum(ranged)), rep("<=", sum(ranged)))
  range_rhs <- c(targets[ranged], maxima[ranged])
  range_names <- c(paste(nutrient_labels[ranged], "(min)"),
                   paste(nutrient_labels[ranged], "(max)"))
  mass_balance <- rep(1, n_ing)  # sum of inclusion rates = 1 (i.e. 100 %)

  if (least_cost) {
    # Variables: x_1..x_n
    open <- !ranged  # nutrients whose target is a plain minimum
    var_names <- ingredients[[label_col]]
    f.obj <- ingredients$cost
    f.con <- rbind(A[open, , drop = FALSE], range_con, mass_balance)
    f.dir <- c(rep(">=", sum(open)), range_dir, "=")
    f.rhs <- c(targets[open], range_rhs, 1)
    con_names <- c(paste(nutrient_labels[open], "(min)"), range_names,
                   "Sum of inclusion rates")
  } else {
    # Variables: x_1..x_n, then under_j and over_j for every goal nutrient
    goal <- which(!ranged)
    n_goal <- length(goal)
    var_names <- c(ingredients[[label_col]],
                   paste0("under[", nutrient_labels[goal], "]"),
                   paste0("over[", nutrient_labels[goal], "]"))
    f.obj <- c(rep(0, n_ing), rep(1, 2 * n_goal))
    pad <- function(m) cbind(m, matrix(0, nrow(m), 2 * n_goal))
    f.con <- rbind(
      cbind(A[goal, , drop = FALSE], diag(n_goal), -diag(n_goal)),
      pad(range_con),
      pad(matrix(mass_balance, nrow = 1))
    )
    f.dir <- c(rep("=", n_goal), range_dir, "=")
    f.rhs <- c(targets[goal], range_rhs, 1)
    con_names <- c(paste(nutrient_labels[goal], "(target)"), range_names,
                   "Sum of inclusion rates")
  }

  log_object(log_context, "LP model (objective: minimise):", {
    model <- as.data.frame(rbind(f.obj, unname(f.con)))
    names(model) <- var_names
    model$dir <- c("", f.dir)
    model$rhs <- c(NA, f.rhs)
    rownames(model) <- c("objective", con_names)
    model
  })

  result <- tryCatch(
    lp("min", f.obj, f.con, f.dir, f.rhs),
    error = function(e) {
      log_error(log_context, "lpSolve failed: ", conditionMessage(e))
      list(status = -1, solution = rep(NA_real_, length(f.obj)),
           objval = NA_real_, error = conditionMessage(e))
    }
  )
  log_info(log_context, "Solver status ", result$status, " (",
           lp_status_text(result$status), "), objective = ", fmt_num(result$objval))

  inclusion <- result$solution[seq_len(n_ing)]
  names(inclusion) <- ingredients[[label_col]]
  achieved <- set_names(as.vector(A %*% inclusion), nutrients)
  feasible <- result$status == 0

  diagnosis <- character()
  if (feasible) {
    log_object(log_context, "Inclusion rates (fraction of the mix):",
               round(inclusion, 6))
    log_object(log_context, "Achieved composition:",
               set_names(round(achieved, 4), nutrient_labels))
  } else if (!is.null(result$error)) {
    diagnosis <- paste("The solver reported an error:", result$error)
  } else {
    diagnosis <- diagnose_infeasibility(
      A, targets, maxima, least_cost, nutrient_labels, log_context
    )
    log_warn(log_context, "No feasible solution. ", paste(diagnosis, collapse = " "))
  }

  list(
    feasible   = feasible,
    mode       = mode,
    inclusion  = inclusion,
    targets    = targets,
    maxima     = maxima,
    achieved   = achieved,
    labels     = nutrient_labels,
    total_cost = sum(ingredients$cost * inclusion),
    objective  = result$objval,
    status     = result$status,
    diagnosis  = diagnosis
  )
}


#' Human-readable description of an lpSolve status code.
lp_status_text <- function(status) {
  switch(as.character(status),
         "0" = "optimal solution found",
         "2" = "infeasible",
         "3" = "unbounded",
         "-1" = "solver error",
         "other solver problem")
}


#' Explain why no mix satisfies the hard constraints
#'
#' Hard constraints are the min-max ranges and, in least-cost mode, also the
#' plain minimum targets. The mix composition is a weighted average of the
#' ingredients, so
#'   1. a single constraint is impossible if the required range does not
#'      overlap the range spanned by the selected ingredients
#'      [min_i a_ij, max_i a_ij];
#'   2. otherwise, every pair of constraints is tested with a small LP to find
#'      combinations that cannot be met at the same time.
#'
#' @param A nutrient matrix (nutrients x ingredients).
#' @param targets,maxima,least_cost as in formulate_feed().
#' @param labels display names of the nutrients.
#' @param log_context tag used in log messages.
#' @return character vector with one explanation per line.
diagnose_infeasibility <- function(A, targets, maxima, least_cost, labels,
                                   log_context = "lp") {
  hard <- !is.na(maxima) | least_cost  # nutrients with hard constraints
  lower <- ifelse(hard, targets, -Inf)
  upper <- ifelse(is.na(maxima), Inf, maxima)
  describe <- function(j) {
    if (is.finite(upper[j])) {
      sprintf("%s between %s and %s", labels[j], fmt_num(lower[j]), fmt_num(upper[j]))
    } else {
      sprintf("%s of at least %s", labels[j], fmt_num(lower[j]))
    }
  }

  # 1. Constraints that no mix of the selected ingredients can reach
  lowest <- apply(A, 1, min)
  highest <- apply(A, 1, max)
  impossible <- which(hard & (highest < lower - 1e-9 | lowest > upper + 1e-9))
  if (length(impossible) > 0) {
    return(c(
      "The following requirement(s) cannot be met by any mix of the selected ingredients:",
      sprintf("  - %s: the selected ingredients contain between %s and %s.",
              map_chr(impossible, describe),
              map_chr(lowest[impossible], fmt_num),
              map_chr(highest[impossible], fmt_num)),
      "Adjust the minimum/maximum or select ingredients richer/poorer in these nutrients."
    ))
  }

  # 2. Pairs of constraints that conflict with each other
  hard_idx <- which(hard)
  conflicts <- character()
  if (length(hard_idx) >= 2) {
    for (pair in combn(hard_idx, 2, simplify = FALSE)) {
      con <- rbind(A[pair, , drop = FALSE], A[pair, , drop = FALSE], rep(1, ncol(A)))
      dir <- c(">=", ">=", "<=", "<=", "=")
      rhs <- c(lower[pair], upper[pair], 1)
      keep <- is.finite(rhs)
      status <- lp("min", rep(0, ncol(A)), con[keep, , drop = FALSE],
                   dir[keep], rhs[keep])$status
      log_debug(log_context, "Feasibility check ", labels[pair[1]], " + ",
                labels[pair[2]], ": ", lp_status_text(status))
      if (status != 0) {
        conflicts <- c(conflicts, sprintf("  - %s and %s", describe(pair[1]), describe(pair[2])))
      }
    }
  }
  if (length(conflicts) > 0) {
    return(c(
      "Each requirement can be met on its own, but these combinations cannot be met at the same time:",
      conflicts,
      "Widen the ranges or select additional ingredients."
    ))
  }

  c(
    "Each requirement can be met on its own, but not all of them at the same time.",
    "Widen the minimum-maximum ranges or select additional ingredients."
  )
}


#' Format the result of formulate_feed() as printable text
#'
#' @param result list returned by formulate_feed().
#' @return character vector, one element per output line.
format_solution <- function(result) {
  if (!result$feasible) {
    return(c("No feasible solution found.", "", result$diagnosis))
  }

  title <- if (result$mode == "least_cost") {
    "Optimal least-cost feed mix"
  } else {
    "Optimal feed mix (minimising deviation from nutrient targets)"
  }

  # Inclusion rates, largest first; ingredients with ~0 inclusion are omitted
  inclusion <- sort(result$inclusion, decreasing = TRUE)
  inclusion <- inclusion[inclusion > 1e-6]
  label_width <- max(nchar(names(inclusion)), 10)
  mix_lines <- sprintf(
    "  %-*s %6.2f %%   (%6.2f kg per 100 kg)",
    label_width, names(inclusion), 100 * inclusion, 100 * inclusion
  )

  # Difference to the target, or "in range" for nutrients with a maximum
  ranged <- !is.na(result$maxima)
  difference <- sprintf("%.2f", round(result$achieved - result$targets, 2) + 0)  # + 0 avoids "-0.00"
  difference[ranged] <- "in range"
  maximum <- ifelse(ranged, sprintf("%.2f", result$maxima), "-")

  nut_width <- max(nchar(result$labels), 18)
  nut_lines <- sprintf(
    "  %-*s %10.2f %10s %10.2f %10s",
    nut_width, result$labels, result$targets, maximum, result$achieved, difference
  )

  cost_line <- if (is.na(result$total_cost)) {
    "Cost of the mix: not available (enter costs for all selected ingredients)."
  } else {
    sprintf("Cost of the mix: %.2f per kg (%.2f per 100 kg)",
            result$total_cost, 100 * result$total_cost)
  }

  c(
    paste0(title, ":"),
    mix_lines,
    "",
    "Nutrient composition of the mix:",
    sprintf("  %-*s %10s %10s %10s %10s", nut_width, "",
            "Target/Min", "Maximum", "Achieved", "Difference"),
    nut_lines,
    "",
    if (result$mode == "target_matching") {
      sprintf("Total absolute deviation from targets: %.2f", result$objective)
    },
    cost_line
  )
}


# CSV import ------------------------------------------------------------------

#' Read and validate a user-supplied ingredient CSV file
#'
#' The file must have the same format as the "Available Ingredients" table:
#' one row per ingredient and the columns
#'   ingredient, protein, lipid, carbohydrate, ash, energy
#' Optional columns:
#'   cost      - price per kg; pre-fills the cost column of the selection
#'   category1 - ingredient category (also accepted as "category")
#' Column names are case-insensitive; any other columns are ignored.
#' Both comma-separated files (decimal point) and semicolon-separated files
#' (decimal comma, as exported by Excel in many European locales) are accepted.
#'
#' @param path path to the CSV file.
#' @param log_context tag used in log messages.
#' @return data.frame with columns ingredient, NUTRIENTS and, if present,
#'   category1 and cost.
#' @throws an error with a user-readable message if the file is invalid.
read_ingredient_csv <- function(path, log_context = "import") {
  # Guess the delimiter from the header line; numbers are parsed below, so
  # all columns are read as text first
  header <- readLines(path, n = 1, warn = FALSE)
  delim <- if (str_count(header, ";") > str_count(header, ",")) ";" else ","
  data <- read_delim(path, delim = delim, show_col_types = FALSE,
                     col_types = cols(.default = col_character()))
  log_debug(log_context, "CSV delimiter '", delim, "', ", nrow(data), " rows, columns: ",
            paste(names(data), collapse = ", "))

  names(data) <- str_to_lower(str_trim(names(data)))
  if (!"category1" %in% names(data) && "category" %in% names(data)) {
    data <- rename(data, category1 = "category")
  }

  required <- c("ingredient", NUTRIENTS)
  missing_cols <- setdiff(required, names(data))
  if (length(missing_cols) > 0) {
    stop("The file is missing the required column(s): ",
         paste(missing_cols, collapse = ", "), ".", call. = FALSE)
  }
  if (nrow(data) == 0) {
    stop("The file does not contain any ingredients.", call. = FALSE)
  }

  # Ingredient names: non-empty and unique
  data$ingredient <- str_trim(data$ingredient)
  if (any(is.na(data$ingredient) | data$ingredient == "")) {
    stop("Every row needs a non-empty 'ingredient' name.", call. = FALSE)
  }
  dups <- unique(data$ingredient[duplicated(data$ingredient)])
  if (length(dups) > 0) {
    stop("Ingredient names must be unique. Duplicated: ",
         paste(dups, collapse = ", "), ".", call. = FALSE)
  }

  for (col in NUTRIENTS) {
    values <- parse_decimal(data[[col]])
    bad <- which(is.na(values))
    if (length(bad) > 0) {
      stop("Column '", col, "' must contain a number in every row. ",
           "Problem in row(s): ", paste(head(bad, 10), collapse = ", "), ".",
           call. = FALSE)
    }
    data[[col]] <- values
  }

  if ("cost" %in% names(data)) {
    raw <- data$cost
    data$cost <- parse_decimal(raw)
    bad <- which((is.na(data$cost) & !is.na(raw) & str_trim(raw) != "") |
                   (!is.na(data$cost) & data$cost < 0))
    if (length(bad) > 0) {
      stop("Column 'cost' must be empty or a non-negative number. ",
           "Problem in row(s): ", paste(head(bad, 10), collapse = ", "), ".",
           call. = FALSE)
    }
  }

  keep <- intersect(c("category1", "ingredient", NUTRIENTS, "cost"), names(data))
  ignored <- setdiff(names(data), keep)
  if (length(ignored) > 0) {
    log_debug(log_context, "Ignored CSV column(s): ", paste(ignored, collapse = ", "))
  }
  as.data.frame(data[, keep])
}
