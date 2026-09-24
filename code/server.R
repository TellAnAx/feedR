# =============================================================================
# server.R - top-level server function
#
# Starts the server logic of every tab module. The ids must match the ids
# used for the corresponding UI functions in code/ui.R.
# =============================================================================

server <- function(input, output, session) {
  session_id <- substr(session$token, 1, 8)
  log_info("session", "New session ", session_id, " started")
  session$onSessionEnded(function() log_info("session", "Session ", session_id, " ended"))

  server_summary("summary")
  server_full("full")
  server_import("import")
  server_manual("manual")
}
