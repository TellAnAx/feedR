# Tests for code/logging.R

test_that("current_log_level() reads the option, then the env variable, then defaults to DEBUG", {
  withr::local_options(feedr.log_level = NULL)
  withr::local_envvar(FEEDR_LOG_LEVEL = NA)
  expect_equal(current_log_level(), "DEBUG")

  withr::local_envvar(FEEDR_LOG_LEVEL = "warn")
  expect_equal(current_log_level(), "WARN")

  withr::local_options(feedr.log_level = "info")
  expect_equal(current_log_level(), "INFO")  # option wins, case-insensitive
})

test_that("current_log_level() falls back to DEBUG for unknown levels", {
  withr::local_options(feedr.log_level = "VERBOSE")
  expect_equal(current_log_level(), "DEBUG")
})

test_that("log_msg() writes one formatted line as a message", {
  withr::local_options(feedr.log_level = "DEBUG")
  expect_message(
    log_msg("INFO", "full", "Added ", 3, " ingredients"),
    "^\\d{2}:\\d{2}:\\d{2}\\.\\d{3} \\[INFO \\] \\[full\\] Added 3 ingredients\\n$"
  )
})

test_that("messages below the active level are suppressed", {
  withr::local_options(feedr.log_level = "WARN")
  expect_no_message(log_debug("ctx", "hidden"))
  expect_no_message(log_info("ctx", "hidden"))
  expect_message(log_warn("ctx", "shown"), "\\[WARN \\] \\[ctx\\] shown")
  expect_message(log_error("ctx", "shown"), "\\[ERROR\\] \\[ctx\\] shown")
})

test_that("log_msg() returns NULL invisibly", {
  withr::local_options(feedr.log_level = "ERROR")
  expect_invisible(log_info("ctx", "x"))
  expect_null(log_info("ctx", "x"))
})

test_that("log_object() prints the object indented below a title at DEBUG level", {
  withr::local_options(feedr.log_level = "DEBUG")
  msg <- capture_messages(log_object("ctx", "A table:", data.frame(a = 1:2)))
  expect_length(msg, 1)
  expect_match(msg, "\\[DEBUG\\] \\[ctx\\] A table:\n")
  expect_match(msg, "\n      a\n    1 1\n    2 2\n$")
})

test_that("log_object() prints nothing above DEBUG and restores the width option", {
  withr::local_options(feedr.log_level = "INFO", width = 80)
  expect_no_message(log_object("ctx", "A table:", 1:3))

  withr::local_options(feedr.log_level = "DEBUG")
  suppressMessages(log_object("ctx", "A table:", 1:3))
  expect_equal(getOption("width"), 80)
})

test_that("fmt_num() formats a vector compactly into one string", {
  expect_equal(fmt_num(40), "40")
  expect_equal(fmt_num(c(40, 10.5, NA)), "40.0, 10.5, NA")
  expect_equal(fmt_num(1 / 3), "0.3333")
})

test_that("fmt_num_each() formats every element separately", {
  expect_equal(fmt_num_each(c(40, 10.5, NA)), c("40", "10.5", "NA"))
  expect_equal(fmt_num_each(numeric(0)), character(0))
})
