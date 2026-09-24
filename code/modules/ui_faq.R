# =============================================================================
# ui_faq.R - UI of the "FAQ" tab
#
# Static help page. Explains how the formulation works (linear programming),
# how to use the tabs and the expected CSV format. Formulas are written in
# LaTeX and rendered with MathJax via withMathJax().
# =============================================================================

#' @param id module id (the FAQ has no server logic).
ui_faq <- function(id) {
  ns <- NS(id)

  fluidPage(
    withMathJax(),
    div(
      class = "faq",

      h3("What does FeedR do?"),
      p(
        "FeedR calculates how much of each selected ingredient to include in",
        "a feed so that the mix reaches a targeted nutrient composition",
        "(protein, lipid, carbohydrate, ash and gross energy). It can either",
        "find the mix that comes closest to the targets, or the cheapest mix",
        "that meets them (least-cost formulation)."
      ),
      tags$ul(
        tags$li(tags$b("Simplified:"), "formulate with ingredient categories",
                "(fish, plant, oil, ...). Their nutrient values are the",
                "averages of all ingredients in the category."),
        tags$li(tags$b("Full:"), "formulate with the individual ingredients",
                "of the feed ingredient database."),
        tags$li(tags$b("Import:"), "formulate with your own ingredient list",
                "uploaded as a CSV file.")
      ),

      h3("How is the formulation calculated?"),
      p(
        "Feed formulation is a classic application of", tags$b("linear programming"),
        "(LP): an optimisation method that finds the best value of a linear",
        "objective function subject to linear equality and inequality",
        "constraints. FeedR builds such a model from your selection and solves",
        "it with the simplex algorithm of the",
        tags$a(href = "https://cran.r-project.org/package=lpSolve", "lpSolve"),
        "R package."
      ),

      h4("Decision variables"),
      p(
        "For every selected ingredient \\(i = 1, \\dots, n\\) the model has one",
        "variable \\(x_i\\): the ingredient's inclusion rate, i.e. its share",
        "of the final mix. Inclusion rates cannot be negative and must add up",
        "to 100 %:"
      ),
      p("$$x_i \\ge 0, \\qquad \\sum_{i=1}^{n} x_i = 1$$"),

      h4("Nutrient composition of the mix"),
      p(
        "If \\(a_{ij}\\) is the content of nutrient \\(j\\) in ingredient",
        "\\(i\\) (e.g. 65 % protein in a fish meal), the content of nutrient",
        "\\(j\\) in the mix is the inclusion-weighted average"
      ),
      p("$$\\sum_{i=1}^{n} a_{ij} \\, x_i .$$"),
      p(
        "This expression is linear in the \\(x_i\\), which is what makes the",
        "problem solvable with linear programming. Example: 30 % of an",
        "ingredient with 60 % protein and 70 % of an ingredient with 20 %",
        "protein give \\(0.3 \\cdot 60 + 0.7 \\cdot 20 = 32\\) % protein."
      ),

      h4("Mode 1: closest match to the targets (default)"),
      p(
        "Usually no mix hits every target \\(t_j\\) exactly. FeedR therefore",
        "adds two helper variables per nutrient: \\(u_j\\) (how far the mix",
        "falls short of the target) and \\(o_j\\) (how far it exceeds it),",
        "and minimises their sum (this technique is called goal programming):"
      ),
      p(paste(
        "$$\\begin{aligned}",
        "\\min \\quad & \\sum_{j} (u_j + o_j) \\\\",
        "\\text{s.t.} \\quad & \\sum_{i} a_{ij} \\, x_i + u_j - o_j = t_j",
        "\\quad \\text{for every nutrient } j \\\\",
        "& \\sum_{i} x_i = 1 \\\\",
        "& x_i, \\, u_j, \\, o_j \\ge 0",
        "\\end{aligned}$$"
      )),
      p(
        "The result is the mix with the smallest total absolute deviation from",
        "the targets. Note that deviations are added up in their own units",
        "(percentage points for protein, lipid, carbohydrate and ash; MJ/kg for",
        "energy), so all nutrients are weighted equally per unit."
      ),

      h4("Mode 2: least-cost formulation"),
      p(
        "When", tags$em("Perform Least-Cost Formulation"), "is ticked, each",
        "ingredient needs a cost \\(c_i\\) per kg (entered in the Selected",
        "Ingredients table or supplied in an imported CSV). FeedR then looks",
        "for the cheapest mix that provides", tags$b("at least"), "the",
        "targeted amount of every nutrient:"
      ),
      p(paste(
        "$$\\begin{aligned}",
        "\\min \\quad & \\sum_{i} c_i \\, x_i \\\\",
        "\\text{s.t.} \\quad & \\sum_{i} a_{ij} \\, x_i \\ge t_j",
        "\\quad \\text{for every nutrient } j \\\\",
        "& \\sum_{i} x_i = 1 \\\\",
        "& x_i \\ge 0",
        "\\end{aligned}$$"
      )),
      p(
        "If the selected ingredients cannot reach all targets at the same",
        "time, the problem is", tags$em("infeasible"), "and FeedR reports",
        "that no solution was found. Lower the targets or add ingredients",
        "that are rich in the limiting nutrient(s)."
      ),

      h4("Reading the solution"),
      tags$ul(
        tags$li("Inclusion rates are given in % of the mix, which is the same",
                "as kg per 100 kg of feed. Ingredients the optimiser did not",
                "use are omitted."),
        tags$li("The nutrient table compares the targets with the composition",
                "actually achieved by the mix."),
        tags$li("The cost of the mix is shown whenever costs are available for",
                "all selected ingredients.")
      ),

      h4("Current limitations"),
      tags$ul(
        tags$li("Only the five nutrients listed above are considered;",
                "amino acids, minerals, digestibility etc. are not."),
        tags$li("There are no minimum or maximum inclusion limits per",
                "ingredient, so the optimiser may use a single ingredient at",
                "a very high rate."),
        tags$li("In least-cost mode every target is a minimum; there are no",
                "upper limits (e.g. a maximum ash content).")
      ),

      h3("How do I enter ingredient costs?"),
      p(
        "Select ingredients in the Available Ingredients table, then",
        "double-click a cell in the", tags$em("Cost (per kg)"), "column of",
        "the Selected Ingredients table, type the price and click outside the",
        "cell (or press Tab) to save it.",
        "Only the cost column can be edited; nutrient values are fixed.",
        "Any currency can be used, as long as it is the same for all",
        "ingredients."
      ),

      h3("Which CSV format does the Import tab expect?"),
      p(
        "The same format as the Available Ingredients table: one row per",
        "ingredient with the following columns (column names are not",
        "case-sensitive, additional columns are ignored):"
      ),
      tags$table(
        class = "table table-condensed",
        tags$thead(tags$tr(tags$th("Column"), tags$th("Content"), tags$th("Required"))),
        tags$tbody(
          tags$tr(tags$td("ingredient"), tags$td("Unique ingredient name"), tags$td("yes")),
          tags$tr(tags$td("protein"), tags$td("Crude protein (%)"), tags$td("yes")),
          tags$tr(tags$td("lipid"), tags$td("Crude lipids (%)"), tags$td("yes")),
          tags$tr(tags$td("carbohydrate"), tags$td("Total carbohydrates (%)"), tags$td("yes")),
          tags$tr(tags$td("ash"), tags$td("Ash (%)"), tags$td("yes")),
          tags$tr(tags$td("energy"), tags$td("Gross energy (MJ/kg)"), tags$td("yes")),
          tags$tr(tags$td("cost"), tags$td("Price per kg; may be left empty"), tags$td("no")),
          tags$tr(tags$td("category"), tags$td("Ingredient category"), tags$td("no"))
        )
      ),
      p(
        "Both comma-separated files (with a decimal point) and",
        "semicolon-separated files (with a decimal comma, as saved by Excel",
        "in many European locales) are accepted. A template can be downloaded",
        "on the Import tab."
      )
    )
  )
}
