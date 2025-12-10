ui <- fluidPage(
  
  # HEADER----
  titlePanel(
    title = "FeedR: Linear Feed Formulation with R",
    windowTitle = "FeedR"
    ),
  
  
  # TABS----
  tabsetPanel(
    # tabPanel("Simplified", ui_summary("summary")),
    tabPanel("Full", ui_full("full"))
    # tabPanel("FAQ", ui_faq("faq"))
  ),
  
  
  # FOOTER----
  tags$br(), tags$br(),
  tags$text("You are using FeedR v0.0.1"),
  tags$br(),
  tags$b("Written by:"),
  tags$a(href = "https://anil.tellbuescher.online", "Anıl Axel Tellbüscher"),
  tags$text(", University of South Bohemia, Czech Republic."),
  tags$br(),
  tags$b("Reporting issues:"),
  tags$text("Please report issues via"),
  tags$a(href = "https://github.com/TellAnAx/feedR/issues", "GitHub"),
  tags$text(" or contact the admin via email:"),
  tags$a(href = "mailto:admin@tellbuescher.online", "admin@tellbuescher.online"),
  tags$br(), tags$br()
  )