# Tests for formulate_feed() (code/helper_functions.R)
#
# The one-part fixture (make_two_ingredients(): A = 60, B = 20, costs 1 and 2)
# has solutions that can be checked by hand.

# Replaces lp() as seen by formulate_feed() for the rest of the test and
# records the arguments of every call in the returned environment.
local_mock_lp <- function(fake = NULL, env = parent.frame()) {
  calls <- new.env()
  calls$args <- list()
  real_lp <- lpSolve::lp
  mock <- function(direction, objective.in, const.mat, const.dir, const.rhs, ...) {
    calls$args[[length(calls$args) + 1]] <- list(
      direction = direction, objective = objective.in, const.mat = const.mat,
      const.dir = const.dir, const.rhs = const.rhs
    )
    if (is.null(fake)) {
      real_lp(direction, objective.in, const.mat, const.dir, const.rhs, ...)
    } else {
      fake(...)
    }
  }
  code_env <- environment(formulate_feed)
  assign("lp", mock, envir = code_env)
  withr::defer(rm("lp", envir = code_env), envir = env)
  calls
}


# Target matching ---------------------------------------------------------------

test_that("target matching hits a reachable target exactly", {
  result <- formulate_p1(make_two_ingredients(), target = 40)

  expect_true(result$feasible)
  expect_equal(result$mode, "target_matching")
  expect_equal(result$status, 0)
  expect_equal(unname(result$inclusion), c(0.5, 0.5))
  expect_equal(unname(result$achieved), 40)
  expect_equal(result$objective, 0)
})

test_that("target matching gets as close as possible to an unreachable target", {
  result <- formulate_p1(make_two_ingredients(), target = 70)

  expect_true(result$feasible)
  expect_equal(unname(result$inclusion), c(1, 0))
  expect_equal(unname(result$achieved), 60)
  expect_equal(result$objective, 10)  # absolute deviation from 70
})

test_that("a min-max range is a hard constraint without deviation cost", {
  result <- formulate_p1(make_two_ingredients(), target = 40, maximum = 50)

  expect_true(result$feasible)
  expect_equal(result$objective, 0)
  expect_gte(result$achieved[["p1"]], 40 - 1e-9)
  expect_lte(result$achieved[["p1"]], 50 + 1e-9)
})


# Least cost ----------------------------------------------------------------------

test_that("least cost picks the cheapest mix meeting every minimum", {
  result <- formulate_p1(make_two_ingredients(), target = 40, least_cost = TRUE)

  expect_true(result$feasible)
  expect_equal(result$mode, "least_cost")
  expect_equal(unname(result$inclusion), c(1, 0))  # A is cheaper and richer
  expect_equal(result$total_cost, 1)
  expect_equal(result$objective, 1)
})

test_that("least cost respects the maximum of a range", {
  # p1 <= 50 allows at most 75 % of A: 0.75 * 60 + 0.25 * 20 = 50
  result <- formulate_p1(make_two_ingredients(), target = 40, maximum = 50,
                         least_cost = TRUE)

  expect_equal(unname(result$inclusion), c(0.75, 0.25))
  expect_equal(unname(result$achieved), 50)
  expect_equal(result$total_cost, 1.25)
})


# Inclusion limits ------------------------------------------------------------------

test_that("maximum inclusion rates cap an ingredient", {
  result <- formulate_p1(make_two_ingredients(max_inclusion = c(30, NA)), target = 60)

  expect_equal(unname(result$inclusion), c(0.3, 0.7))
  expect_equal(unname(result$inclusion_max), c(0.3, NA))
})

test_that("minimum inclusion rates force an ingredient into the mix", {
  # B >= 60 % leaves at most 0.4 * 60 + 0.6 * 20 = 36 for p1
  result <- formulate_p1(make_two_ingredients(min_inclusion = c(NA, 60)), target = 40)

  expect_equal(unname(result$inclusion), c(0.4, 0.6))
  expect_equal(result$objective, 4)
  expect_equal(unname(result$inclusion_min), c(NA, 0.6))
})

test_that("limits that make the requirements unreachable give an infeasible result", {
  result <- formulate_p1(make_two_ingredients(max_inclusion = c(30, NA)), target = 40,
                         least_cost = TRUE)

  expect_false(result$feasible)
  expect_equal(result$status, 2)
  expect_match(result$diagnosis[2], "P1 of at least 40: the selected ingredients can provide between 20 and 32 \\(within their inclusion limits\\)")
})


# General properties ------------------------------------------------------------------

test_that("inclusion rates always sum to 1 and are named after label_col", {
  result <- formulate_feed(make_ingredients(), targets = nutrient_vector(40, 10, 20, 8, 18))

  expect_equal(sum(result$inclusion), 1)
  expect_true(all(result$inclusion >= 0))
  expect_named(result$inclusion, c("Fish meal", "Soybean meal", "Fish oil"))
  expect_named(result$achieved, NUTRIENTS)
  expect_equal(result$labels, unname(NUTRIENT_LABELS))
})

test_that("the achieved composition is the inclusion-weighted average", {
  ingredients <- make_ingredients()
  result <- formulate_feed(ingredients, targets = nutrient_vector(40, 10, 20, 8, 18))

  expected <- colSums(ingredients[, NUTRIENTS] * result$inclusion)
  expect_equal(result$achieved, expected)
})

test_that("custom composition parts and labels are used", {
  result <- formulate_p1(make_two_ingredients(), target = 40)

  expect_named(result$targets, "p1")
  expect_named(result$achieved, "p1")
  expect_equal(result$labels, "P1")
})

test_that("maxima = NULL means no ranges", {
  result <- formulate_feed(make_ingredients(), targets = nutrient_vector(40, 10, 20, 8, 18))
  expect_true(all(is.na(result$maxima)))
})

test_that("total cost is NA when some costs or the cost column are missing", {
  targets <- nutrient_vector(40, 10, 20, 8, 18)
  expect_true(is.na(formulate_feed(make_ingredients(cost = c(1, NA, 2)), targets)$total_cost))

  no_cost <- make_ingredients()
  no_cost$cost <- NULL
  expect_true(is.na(formulate_feed(no_cost, targets)$total_cost))
})


# Arguments passed to lpSolve::lp() ----------------------------------------------

test_that("least cost passes the documented objective, matrix, directions and rhs to lp()", {
  calls <- local_mock_lp()
  ingredients <- make_ingredients(min_inclusion = c(NA, NA, 2), max_inclusion = c(NA, 60, NA))
  targets <- nutrient_vector(38, 8, 15, 8, 18)
  maxima <- nutrient_vector(protein = 42)

  formulate_feed(ingredients, targets, maxima, least_cost = TRUE)

  expect_length(calls$args, 1)
  args <- calls$args[[1]]
  A <- t(as.matrix(ingredients[, NUTRIENTS]))
  expect_equal(args$direction, "min")
  expect_equal(args$objective, ingredients$cost)
  expect_equal(unname(args$const.mat), unname(rbind(
    A[c("lipid", "carbohydrate", "ash", "energy"), ],  # plain minimums
    A["protein", ], A["protein", ],                    # protein range
    c(0, 0, 1),                                        # fish oil minimum
    c(0, 1, 0),                                        # soybean meal maximum
    c(1, 1, 1)                                         # mass balance
  )))
  expect_equal(args$const.dir, c(">=", ">=", ">=", ">=", ">=", "<=", ">=", "<=", "="))
  expect_equal(unname(args$const.rhs), c(8, 15, 8, 18, 38, 42, 0.02, 0.60, 1))
})

test_that("target matching adds under/over deviation columns for nutrients without a maximum", {
  calls <- local_mock_lp()
  ingredients <- make_ingredients()
  targets <- nutrient_vector(38, 8, 15, 8, 18)
  maxima <- nutrient_vector(protein = 42)

  formulate_feed(ingredients, targets, maxima, least_cost = FALSE)

  args <- calls$args[[1]]
  n_goal <- 4  # lipid, carbohydrate, ash, energy
  expect_equal(args$objective, c(0, 0, 0, rep(1, 2 * n_goal)))
  expect_equal(dim(args$const.mat), c(n_goal + 2 + 1, 3 + 2 * n_goal))

  # Goal rows: nutrient coefficients, +1 for "under", -1 for "over"
  A <- t(as.matrix(ingredients[, NUTRIENTS]))
  goal_rows <- args$const.mat[1:n_goal, ]
  expect_equal(unname(goal_rows[, 1:3]), unname(A[c("lipid", "carbohydrate", "ash", "energy"), ]))
  expect_equal(unname(goal_rows[, 4:7]), diag(n_goal))
  expect_equal(unname(goal_rows[, 8:11]), -diag(n_goal))

  # Range and mass balance rows have no deviation coefficients
  expect_true(all(args$const.mat[(n_goal + 1):(n_goal + 3), 4:11] == 0))
  expect_equal(args$const.dir, c(rep("=", n_goal), ">=", "<=", "="))
  expect_equal(unname(args$const.rhs), c(8, 15, 8, 18, 38, 42, 1))
})

test_that("solver errors are caught and reported instead of stopping the app", {
  local_mock_lp(fake = function(...) stop("boom"))

  result <- formulate_p1(make_two_ingredients(), target = 40)

  expect_false(result$feasible)
  expect_equal(result$status, -1)
  expect_equal(result$diagnosis, "The solver reported an error: boom")
})
