
ui <- fluidPage(
  titlePanel("Feed Formulation"),
  sidebarLayout(
    sidebarPanel(
      
      wellPanel(
        h4("Ingredient Filters & Options"),
        selectInput("category_filter", "Filter by Category:",
                    choices = c("All", unique(feed_data$Category)),
                    selected = "All")
      ),
      
      wellPanel(
        h4("Targeted Nutrient Composition"),
        numericInput("protein_req", "Protein (%)", value = 20, min = 0, max = 100),
        numericInput("fat_req", "Fat (%)", value = 5, min = 0, max = 100),
        numericInput("carbohydrate_req", "Carbohydrate (%)", value = 8, min = 0, max = 100),
        numericInput("ash_req", "Ash (%)", value = 6, min = 0, max = 100),
        tags$br(),
        numericInput("energy_req", "Energy (MJ/kg)", value = 12, min = 0, max = 100),
        tags$br(),
        checkboxInput("least_cost", "Perform Least-Cost Formulation", value = FALSE),
        actionButton("formulate", "Formulate"),
        actionButton("clear_selection", "Clear Selection")
        
      )
    ),
    
    mainPanel(
      h3("Available Ingredients"),
      DTOutput("feed_table"),
      
      h3("Selected Ingredients"),
      DTOutput("selected_feed_table"),
      
      h3("Solution"),
      verbatimTextOutput("solution_text")
    )
  )
)
