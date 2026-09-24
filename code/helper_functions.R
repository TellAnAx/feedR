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

#' Formulate a feed mix with linear programming
#'
#' The decision variables are the inclusion rates x_i of the selected
#' ingredients, expressed as fractions of the final mix (x_i >= 0,
#' sum(x_i) = 1). The nutrient content of the mix is the inclusion-weighted
#' average of the ingredient nutrient contents, which is linear in x.
#'
#' Two models are available (see also the FAQ tab):
#'
#' * Target matching (`least_cost = FALSE`, goal programming):
#'     minimise   sum_j (under_j + over_j)
#'     subject to sum_i a_ij x_i + under_j - over_j = t_j   for every nutrient j
#'                sum_i x_i = 1
#'                x, under, over >= 0
#'   i.e. the mix whose composition deviates least (in absolute units) from the
#'   targets.
#'
#' * Least cost (`least_cost = TRUE`):
#'     minimise   sum_i c_i x_i
#'     subject to sum_i a_ij x_i >= t_j                      for every nutrient j
#'                sum_i x_i = 1
#'                x >= 0
#'   i.e. the cheapest mix that meets at least every nutrient target.
#'
#' @param ingredients data.frame with columns `label_col`, NUTRIENTS and
#'   (for least-cost formulation) `cost`.
#' @param targets named numeric vector of targets, names = NUTRIENTS.
#' @param least_cost logical; use the least-cost model instead of target
#'   matching.
#' @param label_col name of the column identifying the ingredients.
#' @return A list with elements
#'   * `feasible`: TRUE if the solver found an optimal solution,
#'   * `mode`: "least_cost" or "target_matching",
#'   * `inclusion`: named vector of inclusion fractions (sums to 1),
#'   * `targets`, `achieved`: named nutrient vectors,
#'   * `total_cost`: cost of 1 kg of the mix (NA if costs are missing),
#'   * `objective`: value of the objective function,
#'   * `status`: raw lpSolve status code (0 = optimal, 2 = infeasible, ...).
formulate_feed <- function(ingredients, targets, least_cost = FALSE,
                           label_col = "ingredient") {
  targets <- targets[NUTRIENTS]
  n_ing <- nrow(ingredients)
  n_nut <- length(NUTRIENTS)

  # Nutrient matrix A: one row per nutrient, one column per ingredient
  A <- t(as.matrix(ingredients[, NUTRIENTS]))
  mass_balance <- rep(1, n_ing)  # sum of inclusion rates = 1 (i.e. 100 %)

  if (least_cost) {
    # Variables: x_1..x_n
    f.obj <- ingredients$cost
    f.con <- rbind(A, mass_balance)
    f.dir <- c(rep(">=", n_nut), "=")
    f.rhs <- c(targets, 1)
  } else {
    # Variables: x_1..x_n, under_1..under_m, over_1..over_m
    f.obj <- c(rep(0, n_ing), rep(1, 2 * n_nut))
    f.con <- rbind(
      cbind(A, diag(n_nut), -diag(n_nut)),
      c(mass_balance, rep(0, 2 * n_nut))
    )
    f.dir <- rep("=", n_nut + 1)
    f.rhs <- c(targets, 1)
  }

  result <- lp("min", f.obj, f.con, f.dir, f.rhs)

  inclusion <- result$solution[seq_len(n_ing)]
  names(inclusion) <- ingredients[[label_col]]
  achieved <- as.vector(A %*% inclusion)
  names(achieved) <- NUTRIENTS

  list(
    feasible   = result$status == 0,
    mode       = if (least_cost) "least_cost" else "target_matching",
    inclusion  = inclusion,
    targets    = targets,
    achieved   = achieved,
    total_cost = sum(ingredients$cost * inclusion),
    objective  = result$objval,
    status     = result$status
  )
}


#' Format the result of formulate_feed() as printable text
#'
#' @param result list returned by formulate_feed().
#' @return character vector, one element per output line.
format_solution <- function(result) {
  if (!result$feasible) {
    hint <- if (result$mode == "least_cost") {
      paste(
        "No mix of the selected ingredients meets all nutrient targets.",
        "Try lowering the targets or selecting additional ingredients",
        "(least-cost formulation treats every target as a minimum).",
        sep = "\n"
      )
    } else {
      "The solver could not find a solution for the selected ingredients."
    }
    return(c("No feasible solution found.", "", hint))
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

  nut_lines <- sprintf(
    "  %-18s %10.2f %10.2f %10.2f",
    NUTRIENT_LABELS[NUTRIENTS], result$targets, result$achieved,
    round(result$achieved - result$targets, 2) + 0  # + 0 avoids "-0.00"
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
    sprintf("  %-18s %10s %10s %10s", "", "Target", "Achieved", "Difference"),
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
#' @return data.frame with columns ingredient, NUTRIENTS and, if present,
#'   category1 and cost.
#' @throws an error with a user-readable message if the file is invalid.
read_ingredient_csv <- function(path) {
  # Guess the delimiter from the header line; numbers are parsed below, so
  # all columns are read as text first
  header <- readLines(path, n = 1, warn = FALSE)
  delim <- if (str_count(header, ";") > str_count(header, ",")) ";" else ","
  data <- read_delim(path, delim = delim, show_col_types = FALSE,
                     col_types = cols(.default = col_character()))

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

  # Parses a character column as numbers, accepting "," as decimal separator
  parse_number_col <- function(x) {
    suppressWarnings(as.numeric(str_replace(str_trim(x), ",", ".")))
  }

  for (col in NUTRIENTS) {
    values <- parse_number_col(data[[col]])
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
    data$cost <- parse_number_col(raw)
    bad <- which((is.na(data$cost) & !is.na(raw) & str_trim(raw) != "") |
                   (!is.na(data$cost) & data$cost < 0))
    if (length(bad) > 0) {
      stop("Column 'cost' must be empty or a non-negative number. ",
           "Problem in row(s): ", paste(head(bad, 10), collapse = ", "), ".",
           call. = FALSE)
    }
  }

  keep <- intersect(c("category1", "ingredient", NUTRIENTS, "cost"), names(data))
  as.data.frame(data[, keep])
}
