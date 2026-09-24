# Tests for the checks run before formulating: check_bounds(),
# check_inclusion_limits() (code/helper_functions.R) and
# validate_optional_value() (code/modules/formulation.R)

test_that("check_bounds() accepts complete targets and consistent maxima", {
  expect_equal(check_bounds(c(a = 5, b = 7), c(a = 6, b = NA), c("A", "B")), character())
  expect_equal(check_bounds(c(a = 5), c(a = 5), "A"), character())  # max == min is fine
})

test_that("check_bounds() reports missing targets", {
  expect_equal(check_bounds(c(a = NA, b = 1, c = NA), c(NA, NA, NA), c("A", "B", "C")),
               "Please enter a target for: A, C.")
})

test_that("check_bounds() reports each maximum below its minimum separately", {
  expect_equal(
    check_bounds(c(a = 5, b = 7), c(a = 3, b = 6), c("A", "B")),
    c("A: the maximum (3) is smaller than the minimum (5).",
      "B: the maximum (6) is smaller than the minimum (7).")
  )
})

test_that("check_inclusion_limits() accepts valid and missing limits", {
  expect_equal(check_inclusion_limits(c(10, NA), c(50, NA), c("a", "b")), character())
  expect_equal(check_inclusion_limits(NULL, NULL, c("a", "b")), character())
  expect_equal(check_inclusion_limits(c(0, 100), c(100, 100), c("a", "b")), character())
})

test_that("check_inclusion_limits() reports limits outside 0-100 %", {
  expect_equal(
    check_inclusion_limits(c(-1, NA), c(NA, 101), c("a", "b")),
    c("a: the minimum inclusion rate (-1 %) must be between 0 and 100 %.",
      "b: the maximum inclusion rate (101 %) must be between 0 and 100 %.")
  )
})

test_that("check_inclusion_limits() reports a minimum above the maximum", {
  expect_equal(
    check_inclusion_limits(c(60, NA), c(50, NA), c("fish", "oil")),
    "fish: the minimum inclusion rate (60 %) is larger than the maximum (50 %)."
  )
})

test_that("check_inclusion_limits() reports minimums adding up to more than 100 %", {
  expect_equal(
    check_inclusion_limits(c(60, 50), NULL, c("a", "b")),
    "The minimum inclusion rates add up to 110 %, more than a complete mix (100 %)."
  )
})

test_that("validate_optional_value() accepts empty input and valid numbers", {
  expect_null(validate_optional_value("", NA, "cost"))
  expect_null(validate_optional_value("0", 0, "cost"))
  expect_null(validate_optional_value("2.5", 2.5, "cost"))
  expect_null(validate_optional_value("100", 100, "min_inclusion"))
  expect_null(validate_optional_value("0", 0, "max_inclusion"))
})

test_that("validate_optional_value() rejects invalid costs and limits", {
  expect_match(validate_optional_value("-1", -1, "cost"), "Cost must be")
  expect_match(validate_optional_value("abc", NA, "cost"), "Cost must be")
  expect_match(validate_optional_value("101", 101, "min_inclusion"), "minimum inclusion rate")
  expect_match(validate_optional_value("-5", -5, "max_inclusion"), "maximum inclusion rate")
})
