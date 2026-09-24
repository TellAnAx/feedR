# Tests for format_solution() and inclusion_limit_notes() (code/helper_functions.R)

test_that("inclusion_limit_notes() describes limits and flags reached ones", {
  expect_equal(
    inclusion_limit_notes(
      inclusion = c(0.5, 0.3, 0.4, 0.1),
      min_limit = c(NA, NA, 0.1, 0.1),
      max_limit = c(NA, 0.3, 0.6, NA)
    ),
    c("", "   [max 30 %, max reached]", "   [min 10 %, max 60 %]", "   [min 10 %, min reached]")
  )
})

test_that("an infeasible result shows the diagnosis instead of a mix", {
  result <- list(feasible = FALSE, diagnosis = c("Reason 1.", "Reason 2."))
  expect_equal(format_solution(result),
               c("No feasible solution found.", "", "Reason 1.", "Reason 2."))
})

test_that("a target-matching solution lists mix, composition, deviation and cost", {
  text <- format_solution(formulate_p1(make_two_ingredients(), target = 40))

  expect_equal(text[1], "Optimal feed mix (minimising deviation from nutrient targets):")
  expect_match(text[2], "^  A +50.00 %   \\( 50.00 kg per 100 kg\\)$")
  expect_match(text[3], "^  B +50.00 %")
  expect_true("Nutrient composition of the mix:" %in% text)
  expect_true(any(grepl("^  P1 +40.00 +- +40.00 +0.00$", text)))
  expect_true("Total absolute deviation from targets: 0.00" %in% text)
  expect_true("Cost of the mix: 1.50 per kg (150.00 per 100 kg)" %in% text)
})

test_that("a least-cost solution has no deviation line and marks ranges", {
  text <- format_solution(formulate_p1(make_two_ingredients(), target = 40, maximum = 50,
                                       least_cost = TRUE))

  expect_equal(text[1], "Optimal least-cost feed mix:")
  expect_false(any(grepl("Total absolute deviation", text)))
  expect_true(any(grepl("^  P1 +40.00 +50.00 +50.00 +in range$", text)))
})

test_that("ingredients not used are omitted, unless they have a minimum", {
  unused <- format_solution(formulate_p1(make_two_ingredients(), target = 40, least_cost = TRUE))
  expect_false(any(grepl("^  B ", unused)))  # B has 0 % inclusion

  result <- formulate_p1(make_two_ingredients(min_inclusion = c(NA, 0)), target = 40,
                         least_cost = TRUE)
  expect_true(any(grepl("^  B +0.00 %.*\\[min 0 %, min reached\\]", format_solution(result))))
})

test_that("ingredients are listed by decreasing inclusion", {
  text <- format_solution(formulate_p1(make_two_ingredients(max_inclusion = c(30, NA)), target = 60))
  expect_match(text[2], "^  B +70.00 %")
  expect_match(text[3], "^  A +30.00 %.*\\[max 30 %, max reached\\]")
})

test_that("missing costs are reported instead of a cost of the mix", {
  text <- format_solution(formulate_p1(make_two_ingredients(cost = c(1, NA)), target = 40))
  expect_true("Cost of the mix: not available (enter costs for all selected ingredients)." %in% text)
})

test_that("rounding never prints negative zero", {
  text <- format_solution(formulate_feed(make_ingredients(), nutrient_vector(40, 10, 20, 8, 18)))
  expect_false(any(grepl("-0\\.00", text)))
})
