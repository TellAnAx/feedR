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
#'   `label_col`, NUTRIENTS, `cost`, `max_inclusion`), or NULL if nothing is
#'   selected yet.
#' @param picked data.frame of ingredients to add (rows of an ingredient table).
#'   If it contains `cost` / `max_inclusion` columns, those values are used
#'   as initial values; otherwise they start out as NA (= not entered).
#' @param label_col name of the column that identifies an ingredient
#'   (e.g. "ingredient" or "category1").
#' @return data.frame with columns `label_col`, NUTRIENTS, `cost` and
#'   `max_inclusion` (maximum inclusion rate in % of the mix, NA = no limit).
add_to_selection <- function(selection, picked, label_col) {
  new <- as.data.frame(picked)
  if (!is.null(selection)) {
    new <- new[!new[[label_col]] %in% selection[[label_col]], , drop = FALSE]
  }

  new_rows <- new[, c(label_col, NUTRIENTS), drop = FALSE]
  optional_col <- function(col) {
    if (col %in% names(new)) as.numeric(new[[col]]) else rep(NA_real_, nrow(new))
  }
  new_rows$cost <- optional_col("cost")
  new_rows$max_inclusion <- optional_col("max_inclusion")

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
      labels[bad], fmt_num_each(maxima[bad]), fmt_num_each(targets[bad])
    ))
  }
  problems
}


#' Check per-ingredient maximum inclusion rates before formulating
#'
#' @param max_inclusion numeric vector of maximum inclusion rates in % of the
#'   mix (NA = no limit).
#' @param ingredient_names names of the ingredients (same order).
#' @return character vector of problems (empty if everything is fine).
check_inclusion_limits <- function(max_inclusion, ingredient_names) {
  bad <- !is.na(max_inclusion) & (max_inclusion < 0 | max_inclusion > 100)
  if (any(bad)) {
    return(sprintf("%s: the maximum inclusion rate (%s %%) must be between 0 and 100 %%.",
                   ingredient_names[bad], fmt_num_each(max_inclusion[bad])))
  }
  character()
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
#' Every ingredient can also have a maximum inclusion rate (column
#' `max_inclusion`, in % of the mix, NA = no limit), which adds the hard
#' constraint x_i <= max_inclusion_i / 100 to both models.
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
#' @param ingredients data.frame with columns `label_col`, `nutrients`,
#'   (for least-cost formulation) `cost` and optionally `max_inclusion`.
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
#'   * `inclusion_limits`: named vector of maximum inclusion fractions
#'     (NA = no limit),
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
  # (sprintf, unlike paste, returns nothing for an empty selection)
  range_names <- c(sprintf("%s (min)", nutrient_labels[ranged]),
                   sprintf("%s (max)", nutrient_labels[ranged]))
  mass_balance <- rep(1, n_ing)  # sum of inclusion rates = 1 (i.e. 100 %)

  # Maximum inclusion rate per ingredient: x_i <= limit_i (as fraction)
  inclusion_limits <- if ("max_inclusion" %in% names(ingredients)) {
    ingredients$max_inclusion / 100
  } else {
    rep(NA_real_, n_ing)
  }
  names(inclusion_limits) <- ingredients[[label_col]]
  limited <- which(!is.na(inclusion_limits))
  limit_con <- matrix(0, nrow = length(limited), ncol = n_ing)
  limit_con[cbind(seq_along(limited), limited)] <- 1
  limit_dir <- rep("<=", length(limited))
  limit_rhs <- inclusion_limits[limited]
  limit_names <- sprintf("Max inclusion [%s]", names(inclusion_limits)[limited])
  if (length(limited) > 0) {
    log_info(log_context, "Maximum inclusion limits: ",
             paste0(names(limit_rhs), " <= ", fmt_num_each(100 * limit_rhs), " %",
                    collapse = "; "))
  }

  if (least_cost) {
    # Variables: x_1..x_n
    open <- !ranged  # nutrients whose target is a plain minimum
    var_names <- ingredients[[label_col]]
    f.obj <- ingredients$cost
    f.con <- rbind(A[open, , drop = FALSE], range_con, limit_con, mass_balance)
    f.dir <- c(rep(">=", sum(open)), range_dir, limit_dir, "=")
    f.rhs <- c(targets[open], range_rhs, limit_rhs, 1)
    con_names <- c(sprintf("%s (min)", nutrient_labels[open]), range_names,
                   limit_names, "Sum of inclusion rates")
  } else {
    # Variables: x_1..x_n, then under_j and over_j for every goal nutrient
    goal <- which(!ranged)
    n_goal <- length(goal)
    var_names <- c(ingredients[[label_col]],
                   sprintf("under[%s]", nutrient_labels[goal]),
                   sprintf("over[%s]", nutrient_labels[goal]))
    f.obj <- c(rep(0, n_ing), rep(1, 2 * n_goal))
    pad <- function(m) cbind(m, matrix(0, nrow(m), 2 * n_goal))
    f.con <- rbind(
      cbind(A[goal, , drop = FALSE], diag(n_goal), -diag(n_goal)),
      pad(range_con),
      pad(limit_con),
      pad(matrix(mass_balance, nrow = 1))
    )
    f.dir <- c(rep("=", n_goal), range_dir, limit_dir, "=")
    f.rhs <- c(targets[goal], range_rhs, limit_rhs, 1)
    con_names <- c(sprintf("%s (target)", nutrient_labels[goal]), range_names,
                   limit_names, "Sum of inclusion rates")
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
      A, targets, maxima, least_cost, nutrient_labels, log_context,
      inclusion_limits = inclusion_limits
    )
    log_warn(log_context, "No feasible solution. ", paste(diagnosis, collapse = " "))
  }

  list(
    feasible   = feasible,
    mode       = mode,
    inclusion  = inclusion,
    inclusion_limits = inclusion_limits,
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
#' Hard constraints are the min-max ranges, the maximum inclusion rates and,
#' in least-cost mode, also the plain minimum targets. The checks are
#'   0. the inclusion limits must add up to at least 100 %;
#'   1. a single nutrient requirement is impossible if the required range does
#'      not overlap the range of contents any mix can reach (found by
#'      minimising and maximising the nutrient content with small LPs that
#'      respect the inclusion limits);
#'   2. otherwise, every pair of requirements is tested with a small LP to
#'      find combinations that cannot be met at the same time.
#'
#' @param A nutrient matrix (nutrients x ingredients).
#' @param targets,maxima,least_cost as in formulate_feed().
#' @param labels display names of the nutrients.
#' @param log_context tag used in log messages.
#' @param inclusion_limits maximum inclusion fraction per ingredient
#'   (NA = no limit).
#' @return character vector with one explanation per line.
diagnose_infeasibility <- function(A, targets, maxima, least_cost, labels,
                                   log_context = "lp",
                                   inclusion_limits = rep(NA_real_, ncol(A))) {
  hard <- !is.na(maxima) | least_cost  # nutrients with hard constraints
  lower <- ifelse(hard, targets, -Inf)
  upper <- ifelse(is.na(maxima), Inf, maxima)
  limits <- ifelse(is.na(inclusion_limits), 1, inclusion_limits)
  has_limits <- any(!is.na(inclusion_limits))
  describe <- function(j) {
    if (is.finite(upper[j])) {
      sprintf("%s between %s and %s", labels[j], fmt_num(lower[j]), fmt_num(upper[j]))
    } else {
      sprintf("%s of at least %s", labels[j], fmt_num(lower[j]))
    }
  }

  # Solves an LP over the inclusion rates with the mass balance and the
  # inclusion limits, plus optional extra constraints
  solve_mix <- function(direction, objective, con = NULL, dir = NULL, rhs = NULL) {
    n <- ncol(A)
    lp(direction, objective,
       rbind(con, rep(1, n), diag(n)),
       c(dir, "=", rep("<=", n)),
       c(rhs, 1, limits))
  }

  # 0. The inclusion limits must leave room for a complete (100 %) mix
  if (sum(limits) < 1 - 1e-9) {
    return(c(
      sprintf(paste("The maximum inclusion rates of the selected ingredients add up to",
                    "only %s %%, so they cannot make up a complete mix."),
              fmt_num(100 * sum(limits))),
      "Raise the maximum inclusion rates or select additional ingredients."
    ))
  }

  # 1. Requirements that no mix of the selected ingredients can reach: the
  #    reachable range of each nutrient is found by minimising and maximising
  #    its content (respecting the inclusion limits)
  hard_idx <- which(hard)
  lowest <- set_names(rep(NA_real_, length(labels)), labels)
  highest <- lowest
  for (j in hard_idx) {
    lowest[j] <- solve_mix("min", A[j, ])$objval
    highest[j] <- solve_mix("max", A[j, ])$objval
    log_debug(log_context, "Reachable range of ", labels[j], ": ",
              fmt_num(lowest[j]), " to ", fmt_num(highest[j]))
  }
  impossible <- hard_idx[highest[hard_idx] < lower[hard_idx] - 1e-9 |
                           lowest[hard_idx] > upper[hard_idx] + 1e-9]
  if (length(impossible) > 0) {
    return(c(
      "The following requirement(s) cannot be met by any mix of the selected ingredients:",
      sprintf("  - %s: the selected ingredients can provide between %s and %s%s.",
              map_chr(impossible, describe),
              fmt_num_each(lowest[impossible]),
              fmt_num_each(highest[impossible]),
              if (has_limits) " (within their maximum inclusion rates)" else ""),
      paste("Adjust the minimum/maximum, relax the inclusion limits or select",
            "ingredients richer/poorer in these nutrients.")
    ))
  }

  # 2. Pairs of requirements that conflict with each other
  conflicts <- character()
  if (length(hard_idx) >= 2) {
    for (pair in combn(hard_idx, 2, simplify = FALSE)) {
      con <- rbind(A[pair, , drop = FALSE], A[pair, , drop = FALSE])
      dir <- c(">=", ">=", "<=", "<=")
      rhs <- c(lower[pair], upper[pair])
      keep <- is.finite(rhs)
      status <- solve_mix("min", rep(0, ncol(A)), con[keep, , drop = FALSE],
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
      "Widen the ranges, relax the inclusion limits or select additional ingredients."
    ))
  }

  c(
    "Each requirement can be met on its own, but not all of them at the same time.",
    "Widen the minimum-maximum ranges, relax the inclusion limits or select additional ingredients."
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

  # Inclusion rates, largest first; ingredients with ~0 inclusion are omitted.
  # Ingredients with a maximum inclusion rate show it, flagged when reached.
  used <- order(result$inclusion, decreasing = TRUE)
  used <- used[result$inclusion[used] > 1e-6]
  inclusion <- result$inclusion[used]
  limit <- result$inclusion_limits[used]
  limit_note <- ifelse(
    is.na(limit), "",
    sprintf("   [max %s %%%s]", fmt_num_each(100 * limit),
            ifelse(inclusion >= limit - 1e-6, ", limit reached", ""))
  )
  label_width <- max(nchar(names(inclusion)), 10)
  mix_lines <- sprintf(
    "  %-*s %6.2f %%   (%6.2f kg per 100 kg)%s",
    label_width, names(inclusion), 100 * inclusion, 100 * inclusion, limit_note
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
#'   max_inclusion - maximum inclusion rate in % of the mix; pre-fills the
#'               corresponding column of the selection
#'   category1 - ingredient category (also accepted as "category")
#' Column names are case-insensitive; any other columns are ignored.
#' Both comma-separated files (decimal point) and semicolon-separated files
#' (decimal comma, as exported by Excel in many European locales) are accepted.
#'
#' @param path path to the CSV file.
#' @param log_context tag used in log messages.
#' @return data.frame with columns ingredient, NUTRIENTS and, if present,
#'   category1, cost and max_inclusion.
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

  # Optional columns: empty cells allowed, otherwise a number in [min, max]
  parse_optional <- function(col, min, max, what) {
    raw <- data[[col]]
    values <- parse_decimal(raw)
    bad <- which((is.na(values) & !is.na(raw) & str_trim(raw) != "") |
                   (!is.na(values) & (values < min | values > max)))
    if (length(bad) > 0) {
      stop("Column '", col, "' must be empty or ", what, ". ",
           "Problem in row(s): ", paste(head(bad, 10), collapse = ", "), ".",
           call. = FALSE)
    }
    values
  }
  if ("cost" %in% names(data)) {
    data$cost <- parse_optional("cost", 0, Inf, "a non-negative number")
  }
  if ("max_inclusion" %in% names(data)) {
    data$max_inclusion <- parse_optional("max_inclusion", 0, 100,
                                         "a number between 0 and 100 (%)")
  }

  keep <- intersect(c("category1", "ingredient", NUTRIENTS, "cost", "max_inclusion"),
                    names(data))
  ignored <- setdiff(names(data), keep)
  if (length(ignored) > 0) {
    log_debug(log_context, "Ignored CSV column(s): ", paste(ignored, collapse = ", "))
  }
  as.data.frame(data[, keep])
}
