# =============================================================================
# dependencies.R - R packages required by FeedR
#
#   shiny     - web application framework
#   lpSolve   - linear programming solver used for the formulation
#   tidyverse - data import (readr) and manipulation (dplyr, stringr)
#   DT        - interactive tables
#
# Install them once with
#   install.packages(c("shiny", "lpSolve", "tidyverse", "DT"))
# =============================================================================

library(shiny)
library(lpSolve)
library(tidyverse)
library(DT)
