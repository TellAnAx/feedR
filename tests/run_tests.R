# =============================================================================
# run_tests.R - runs the test suite
#
# From the repository root:
#   Rscript tests/run_tests.R
# or, in an R session started in the repository root:
#   testthat::test_dir("tests/testthat")
#
# Exits with a non-zero status if any test fails, so it can be used in CI.
# =============================================================================

library(testthat)

test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
