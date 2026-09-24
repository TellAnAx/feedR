# Tests for diagnose_infeasibility() and lp_status_text() (code/helper_functions.R)

# Two parts, three ingredients: X is pure p1, Y is pure p2, Z has neither.
# Each part alone can reach 0-100, but not both >= 60 at the same time.
conflict_matrix <- function() {
  matrix(c(100, 0, 0,
           0, 100, 0), nrow = 2, byrow = TRUE,
         dimnames = list(c("P1", "P2"), c("X", "Y", "Z")))
}

test_that("lp_status_text() describes lpSolve status codes", {
  expect_equal(lp_status_text(0), "optimal solution found")
  expect_equal(lp_status_text(2), "infeasible")
  expect_equal(lp_status_text(3), "unbounded")
  expect_equal(lp_status_text(-1), "solver error")
  expect_equal(lp_status_text(5), "other solver problem")
})

test_that("maximum inclusion rates below 100 % in total are reported first", {
  diagnosis <- diagnose_infeasibility(
    conflict_matrix(), targets = c(p1 = 0, p2 = 0), maxima = c(NA, NA),
    least_cost = FALSE, labels = c("P1", "P2"), inclusion_max = c(0.3, 0.3, 0.2)
  )
  expect_match(diagnosis[1], "add up to only 80 %, so they cannot make up a complete mix")
})

test_that("minimum inclusion rates above 100 % in total are reported", {
  diagnosis <- diagnose_infeasibility(
    conflict_matrix(), targets = c(p1 = 0, p2 = 0), maxima = c(NA, NA),
    least_cost = FALSE, labels = c("P1", "P2"), inclusion_min = c(0.7, 0.5, NA)
  )
  expect_match(diagnosis[1], "minimum inclusion rates .* add up to 120 %")
})

test_that("a requirement outside the reachable range is reported on its own", {
  A <- matrix(c(60, 20), nrow = 1, dimnames = list("P1", c("A", "B")))
  diagnosis <- diagnose_infeasibility(A, targets = c(p1 = 70), maxima = c(p1 = 80),
                                      least_cost = FALSE, labels = "P1")
  expect_equal(diagnosis, c(
    "The following requirement(s) cannot be met by any mix of the selected ingredients:",
    "  - P1 between 70 and 80: the selected ingredients can provide between 20 and 60.",
    "Adjust the minimum/maximum, relax the inclusion limits or select ingredients richer/poorer in these nutrients."
  ))
})

test_that("the reachable range takes inclusion limits into account", {
  A <- matrix(c(60, 20), nrow = 1, dimnames = list("P1", c("A", "B")))
  diagnosis <- diagnose_infeasibility(A, targets = c(p1 = 40), maxima = c(p1 = NA),
                                      least_cost = TRUE, labels = "P1",
                                      inclusion_max = c(0.3, NA))
  expect_match(diagnosis[2], "P1 of at least 40: .* between 20 and 32 \\(within their inclusion limits\\)")
})

test_that("in target matching, nutrients without a maximum are not hard requirements", {
  A <- matrix(c(60, 20), nrow = 1, dimnames = list("P1", c("A", "B")))
  diagnosis <- diagnose_infeasibility(A, targets = c(p1 = 70), maxima = c(p1 = NA),
                                      least_cost = FALSE, labels = "P1")
  expect_match(diagnosis[1], "not all of them at the same time")  # nothing specific to report
})

test_that("pairs of requirements that conflict are listed", {
  diagnosis <- diagnose_infeasibility(
    conflict_matrix(), targets = c(p1 = 60, p2 = 60), maxima = c(p1 = 100, p2 = 100),
    least_cost = FALSE, labels = c("P1", "P2")
  )
  expect_equal(diagnosis, c(
    "Each requirement can be met on its own, but these combinations cannot be met at the same time:",
    "  - P1 between 60 and 100 and P2 between 60 and 100",
    "Widen the ranges, relax the inclusion limits or select additional ingredients."
  ))
})

test_that("when every pair is compatible, the general message is returned", {
  # The infeasible example from the README: carbohydrate >= 20 %
  ingredients <- make_ingredients(min_inclusion = c(NA, NA, 2), max_inclusion = c(NA, 60, NA))
  result <- formulate_feed(ingredients, nutrient_vector(38, 8, 20, 8, 18),
                           nutrient_vector(protein = 42), least_cost = TRUE)
  expect_false(result$feasible)
  expect_equal(result$diagnosis[1],
               "Each requirement can be met on its own, but not all of them at the same time.")
})
