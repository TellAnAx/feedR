# =============================================================================
# server.R - top-level server function
#
# Starts the server logic of every tab module. The ids must match the ids
# used for the corresponding UI functions in code/ui.R.
# =============================================================================

server <- function(input, output, session) {
  server_summary("summary")
  server_full("full")
  server_import("import")
}
