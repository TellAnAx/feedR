library(shiny)
library(lpSolve)
library(readr)
library(DT)



source("code/ui.R")
source("code/server.R")


shinyApp(ui, server)
