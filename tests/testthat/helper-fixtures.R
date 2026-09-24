# =============================================================================
# helper-fixtures.R - small, hand-checkable test data
# =============================================================================

#' Three ingredients with simple nutrient values (built-in NUTRIENTS columns).
make_ingredients <- function(cost = c(1.8, 0.6, 2.2),
                             min_inclusion = c(NA, NA, NA),
                             max_inclusion = c(NA, NA, NA)) {
  data.frame(
    ingredient    = c("Fish meal", "Soybean meal", "Fish oil"),
    protein       = c(65, 46, 0),
    lipid         = c(9, 2, 99),
    carbohydrate  = c(2, 35, 0),
    ash           = c(16, 7, 0),
    energy        = c(19, 17.5, 38),
    cost          = cost,
    min_inclusion = min_inclusion,
    max_inclusion = max_inclusion
  )
}

#' Two ingredients with one custom composition part "p1" (60 % and 20 %).
#' Mixing them 50:50 gives exactly 40 %, 75:25 gives 50 %.
make_two_ingredients <- function(cost = c(1, 2), min_inclusion = c(NA, NA),
                                 max_inclusion = c(NA, NA)) {
  data.frame(ingredient = c("A", "B"), p1 = c(60, 20), cost = cost,
             min_inclusion = min_inclusion, max_inclusion = max_inclusion)
}

#' formulate_feed() for the one-part fixture, with less typing.
formulate_p1 <- function(ingredients, target, maximum = NA, least_cost = FALSE) {
  formulate_feed(ingredients, targets = c(p1 = target), maxima = c(p1 = maximum),
                 least_cost = least_cost, nutrients = "p1", nutrient_labels = "P1")
}

#' Named vector with a value for each of the built-in NUTRIENTS.
nutrient_vector <- function(protein = NA, lipid = NA, carbohydrate = NA,
                            ash = NA, energy = NA) {
  c(protein = protein, lipid = lipid, carbohydrate = carbohydrate,
    ash = ash, energy = energy)
}

#' Writes lines to a temporary CSV file that is deleted after the test.
local_csv <- function(lines, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = env)
  writeLines(lines, path)
  path
}
