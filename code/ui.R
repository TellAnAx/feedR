ui <- fluidPage(
  titlePanel("Linear Feed Formulation (No Cost)"),

  sidebarLayout(
    sidebarPanel(
      numericInput("protein_req", "Minimum Crude Protein (%)", value = 30),
      numericInput("energy_req", "Minimum Gross Energy (MJ/kg)", value = 15),
      actionButton("formulate", "Formulate Feed")
    ),

    mainPanel(
      DTOutput("feed_table"),
      DTOutput("selected_feed_table"),
      verbatimTextOutput("solution_text")
    )
  )
)
