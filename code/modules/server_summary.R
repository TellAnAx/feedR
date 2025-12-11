server_summary <- function(id) {
  moduleServer(id, module = function(input, output, session) {
    ns <- session$ns

    # Render feed selection table
    output$feed_table <- renderDT({
      datatable(
        feed_data_summarised[, c("category1", "protein", "lipid", "carbohydrate", "ash", "energy")],
        selection = "multiple",
        filter = "none",
        options = list(pageLength = 10, autoWidth = TRUE)
        )
      })


    # Persistent selection storage
    selected_ingredients <- reactiveVal(data.frame())


    # Update persistent selection
    observeEvent(input$feed_table_rows_selected, {
      current_selection <- feed_data_summarised[input$feed_table_rows_selected, ]
      previous_selection <- selected_ingredients()
      updated_selection <- unique(rbind(previous_selection, current_selection))
      selected_ingredients(updated_selection)
      })


    # Render selected feed table
    output$selected_feed_table <- renderDT({
      if (nrow(selected_ingredients()) > 0) {
        datatable(selected_ingredients() %>%
                    mutate(Cost = 0),
                  editable = TRUE)
      } else {
        datatable(data.frame(Message = "No ingredients selected"))
        }
      })


    # Button: Clear selection
    observeEvent(input$clear_selection, {
      selected_ingredients(data.frame())
    })






    # Formulation logic
    observeEvent(input$formulate, {

      if (nrow(selected_ingredients()) == 0) {
        output$solution_text <- renderPrint({ cat("Please select at least one ingredient.") })
        return(NULL)
      }

      selected_feed <- selected_ingredients()

      # Nutrients and targets
      nutrients <- c("protein", "lipid", "carbohydrate", "ash", "energy")
      targets <- c(input$protein_req, input$fat_req, input$carbohydrate_req, input$ash_req, input$energy_req)
      n_ing <- nrow(selected_feed)
      n_nut <- length(nutrients)

      if (input$least_cost) {
        # Validate cost data
        if (any(selected_feed$Cost == 0)) {
          output$solution_text <- renderPrint({
            cat("Least-cost formulation selected, but cost data is missing.\nPlease enter cost values.")
          })
          return(NULL)
        }

        # Objective: minimize cost
        f.obj <- selected_feed$Cost
        f.con <- do.call(rbind, lapply(nutrients, function(n) selected_feed[[n]]))
        f.dir <- rep(">=", n_nut)  # or mix of >= and <= if needed
        f.rhs <- targets

        result <- lp("min", f.obj, f.con, f.dir, f.rhs)

      } else {
        # Goal programming: minimize deviation from targets
        # Variables: ingredient amounts + 2 deviations per nutrient
        n_vars <- n_ing + 2 * n_nut
        f.obj <- c(rep(0, n_ing), rep(1, 2 * n_nut))  # minimize sum of deviations

        # Build constraint matrix
        f.con <- matrix(0, nrow = n_nut, ncol = n_vars)
        for (i in 1:n_nut) {
          f.con[i, 1:n_ing] <- selected_feed[[nutrients[i]]]  # ingredient contributions
          f.con[i, n_ing + (2 * i - 1)] <- 1   # d+
          f.con[i, n_ing + (2 * i)] <- -1      # d-
        }

        f.dir <- rep("=", n_nut)
        f.rhs <- targets

        result <- lp("min", f.obj, f.con, f.dir, f.rhs)
      }

      # Output results
      if (result$status == 0) {
        amounts <- result$solution[1:n_ing]
        names(amounts) <- selected_feed$category1
        output$solution_text <- renderPrint({
          if (input$least_cost) {
            cat("Optimal Least-Cost Feed Mix (kg):\n")
          } else {
            cat("Optimal Feed Mix (kg) minimizing nutrient deviation:\n")
          }
          print(round(amounts, 2))
          if (input$least_cost) {
            cat("\nTotal Cost:", round(result$objval, 2))
          } else {
            cat("\nTotal Deviation:", round(result$objval, 2))
          }
        })
      } else {
        output$solution_text <- renderPrint({ cat("No feasible solution found.") })
      }
    })
  })
}
