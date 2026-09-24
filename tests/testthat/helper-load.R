# =============================================================================
# helper-load.R - loads the app code for the tests
#
# testthat runs every helper-*.R file before the tests, with tests/testthat
# as working directory. This file sources the packages and all files that
# define helper functions, without data_prep.R (tests use small fixtures
# instead of the ingredient database) and without starting Shiny.
# =============================================================================

app_root <- normalizePath(file.path("..", ".."))

suppressPackageStartupMessages(source(file.path(app_root, "dependencies.R"), local = TRUE))
source(file.path(app_root, "code", "logging.R"), local = TRUE)
source(file.path(app_root, "code", "helper_functions.R"), local = TRUE)
source(file.path(app_root, "code", "modules", "formulation.R"), local = TRUE)

# Keep test output clean; logging tests raise the level where needed
options(feedr.log_level = "ERROR")
