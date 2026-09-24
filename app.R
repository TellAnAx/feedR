# =============================================================================
# app.R - entry point of FeedR
#
# Run the app from the repository root with
#   shiny::runApp()
# All paths below are relative to the repository root.
#
# Files are sourced in dependency order:
#   1. packages
#   2. data (feed_data, feed_data_summarised)
#   3. helper functions and shared formulation module
#   4. tab modules (one UI and one server function per tab)
#   5. top-level UI and server that combine the tabs
# =============================================================================

source("dependencies.R")

source("code/data_prep.R")
source("code/helper_functions.R")

source("code/modules/formulation.R")

source("code/modules/ui_summary.R")
source("code/modules/ui_full.R")
source("code/modules/ui_import.R")
source("code/modules/ui_faq.R")

source("code/modules/server_summary.R")
source("code/modules/server_full.R")
source("code/modules/server_import.R")

source("code/ui.R")
source("code/server.R")


shinyApp(ui, server)
