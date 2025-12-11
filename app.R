source("dependencies.R")

source("code/data_prep.R")



source("code/modules/ui_summary.R")
source("code/modules/ui_full.R")
source("code/modules/ui_faq.R")

source("code/modules/server_summary.R")
source("code/modules/server_full.R")

source("code/ui.R")
source("code/server.R")


shinyApp(ui, server)
