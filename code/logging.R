# =============================================================================
# logging.R - console logging
#
# Everything that happens under the hood (data loading, user actions, the
# linear programs built and their solutions) is written to the R console via
# message(), one line per event:
#
#   14:03:12.345 [INFO ] [full] Formulate clicked: 3 ingredients, least-cost
#
# The amount of detail is controlled by the log level (lowest to highest):
#   DEBUG - everything, including the full LP model and solver output
#   INFO  - user actions and results
#   WARN  - invalid input, infeasible formulations
#   ERROR - unexpected errors
# Set it with the environment variable FEEDR_LOG_LEVEL or the R option
# feedr.log_level (the option wins), e.g.
#   options(feedr.log_level = "INFO"); shiny::runApp()
# The default is DEBUG.
# =============================================================================

LOG_LEVELS <- c(DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4)

#' Currently active log level (falls back to DEBUG if the setting is invalid).
current_log_level <- function() {
  level <- toupper(getOption("feedr.log_level", Sys.getenv("FEEDR_LOG_LEVEL", "DEBUG")))
  if (level %in% names(LOG_LEVELS)) level else "DEBUG"
}

#' Write a log line to the console
#'
#' @param level one of names(LOG_LEVELS).
#' @param context short tag saying where the event happened, e.g. the module
#'   id ("summary", "full", ...) or "data".
#' @param ... message parts, pasted together without separator.
log_msg <- function(level, context, ...) {
  if (LOG_LEVELS[[level]] < LOG_LEVELS[[current_log_level()]]) {
    return(invisible(NULL))
  }
  message(sprintf("%s [%-5s] [%s] %s",
                  format(Sys.time(), "%H:%M:%OS3"), level, context,
                  paste0(...)))
  invisible(NULL)
}

log_debug <- function(context, ...) log_msg("DEBUG", context, ...)
log_info  <- function(context, ...) log_msg("INFO", context, ...)
log_warn  <- function(context, ...) log_msg("WARN", context, ...)
log_error <- function(context, ...) log_msg("ERROR", context, ...)

#' Log a printed R object (e.g. a data.frame or matrix) at DEBUG level
#'
#' The object is printed as usual and every output line is indented below a
#' title line.
#'
#' @param context see log_msg().
#' @param title line written before the object.
#' @param object any R object.
log_object <- function(context, title, object) {
  if (LOG_LEVELS[["DEBUG"]] < LOG_LEVELS[[current_log_level()]]) {
    return(invisible(NULL))
  }
  # Print wide so that tables (e.g. the LP model) are not wrapped
  old <- options(width = 250)
  on.exit(options(old))
  lines <- capture.output(print(object))
  log_debug(context, title, "\n", paste0("    ", lines, collapse = "\n"))
}

#' Format a number vector compactly for log messages, e.g. "40, 10.5, NA".
fmt_num <- function(x) paste(format(x, digits = 4, trim = TRUE), collapse = ", ")

#' Format each number of a vector separately, e.g. c("40", "10.5", "NA").
fmt_num_each <- function(x) vapply(x, fmt_num, character(1), USE.NAMES = FALSE)
