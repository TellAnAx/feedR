# Tests for parse_decimal() (code/helper_functions.R)

test_that("decimal points and decimal commas are accepted", {
  expect_equal(parse_decimal(c("2.5", "2,5", " 3 ", "-1,25")), c(2.5, 2.5, 3, -1.25))
})

test_that("numbers pass through unchanged", {
  expect_equal(parse_decimal(c(1, 2.5)), c(1, 2.5))
})

test_that("empty or non-numeric input becomes NA without warnings", {
  expect_no_warning(result <- parse_decimal(c("", "abc", NA, "1.2.3")))
  expect_equal(result, rep(NA_real_, 4))
})
