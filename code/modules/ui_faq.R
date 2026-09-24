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
                "uploaded as a CSV file."),
        tags$li(tags$b("Manual:"), "define your own composition parts",
                "(any nutrients, with target values) and type in the",
                "available ingredients by hand. All entered ingredients are",
                "used in the formulation.")
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

      h4("Optional maximum: minimum-maximum ranges"),
      p(
        "Every nutrient (and every composition part on the Manual tab) has an",
        "optional", tags$em("Maximum"), "field. If a maximum \\(m_j\\) is",
        "set, the target \\(t_j\\) is treated as a minimum and the mix must",
        "lie within the range, in both modes:"
      ),
      p("$$t_j \\le \\sum_{i} a_{ij} \\, x_i \\le m_j$$"),
      p(
        "In mode 1 such a nutrient is no longer part of the deviation that is",
        "minimised; it is a hard requirement instead. In mode 2 it replaces the",
        "plain minimum. The solution table then shows", tags$em("in range"),
        "for this nutrient."
      ),

      h4("Optional inclusion limits per ingredient"),
      p(
        "Each selected ingredient can also be given a minimum inclusion rate",
        "\\(k_i\\) and/or a maximum inclusion rate \\(l_i\\), in % of the",
        "mix (columns", tags$em("Min. inclusion (%)"), "and",
        tags$em("Max. inclusion (%)"), "in the ingredient tables, or",
        tags$code("min_inclusion"), "/", tags$code("max_inclusion"), "in an",
        "imported CSV). They add hard constraints to both modes:"
      ),
      p("$$\\frac{k_i}{100} \\le x_i \\le \\frac{l_i}{100}$$"),
      p(
        "Use a maximum, for example, to limit an expensive or anti-nutritional",
        "ingredient, and a minimum to force a premix or a binder into the",
        "feed. The solution shows each ingredient's limits and marks those",
        "that were reached. A minimum larger than the maximum, or minimums",
        "that add up to more than 100 %, are reported before the calculation",
        "starts."
      ),

      h4("What if no solution is found?"),
      p(
        "If the selected ingredients cannot satisfy all hard requirements",
        "(ranges, inclusion limits, and in least-cost mode all",
        "minima) at the same time, the",
        "problem is", tags$em("infeasible."), "FeedR then explains why:"
      ),
      tags$ul(
        tags$li("If the maximum inclusion rates add up to less than 100 %, no",
                "complete mix is possible (likewise if the minimums add up to",
                "more than 100 %)."),
        tags$li("A requirement is impossible on its own if the required range",
                "does not overlap the range of contents any mix can reach. The",
                "mix is an average, so it can never contain more of a nutrient",
                "than the richest ingredient, or less than the poorest; FeedR",
                "calculates the exact reachable range, taking the inclusion",
                "limits into account."),
        tags$li("Otherwise, FeedR checks every pair of requirements and lists",
                "the combinations that cannot be met together.")
      ),
      p(
        "Widen the ranges, lower the minima or add ingredients that are rich",
        "(or poor) in the limiting nutrient(s). A maximum below its minimum is",
        "reported before the calculation starts."
      ),

      h4("Reading the solution"),
      tags$ul(
        tags$li("Inclusion rates are given in % of the mix, which is the same",
                "as kg per 100 kg of feed. Ingredients the optimiser did not",
                "use are omitted."),
        tags$li("The nutrient table compares the targets (or minimum and",
                "maximum) with the composition actually achieved by the mix."),
        tags$li("The cost of the mix is shown whenever costs are available for",
                "all selected ingredients.")
      ),

      h4("Current limitations"),
      tags$ul(
        tags$li("Only the five nutrients listed above are considered;",
                "amino acids, minerals, digestibility etc. are not.")
      ),

      h3("How do I enter ingredient costs?"),
      p(
        "Select ingredients in the Available Ingredients table, then",
        "double-click a cell in the", tags$em("Cost (per kg)"), "column of",
        "the Selected Ingredients table, type the price and click outside the",
        "cell (or press Tab) to save it.",
        "Only the cost and inclusion limit columns can be edited; nutrient",
        "values are fixed.",
        "Any currency can be used, as long as it is the same for all",
        "ingredients."
      ),

      h3("How does the Manual tab work?"),
      tags$ol(
        tags$li("Define the composition parts to formulate for, each with a",
                "target value, e.g. \"Protein (%)\" with target 40. The",
                tags$em("Add Standard Nutrients"), "button adds protein,",
                "lipid, carbohydrate, ash and energy in one go."),
        tags$li("Add the available ingredients one by one with their content",
                "of every composition part (in the same units as the target)",
                "and, optionally, their cost per kg and minimum / maximum",
                "inclusion rate."),
        tags$li("Click", tags$em("Formulate."), "All entered ingredients are",
                "used; the model is the same as described above, only with",
                "your composition parts instead of the five standard nutrients.")
      ),
      p(
        "Targets and ingredient values can be corrected by double-clicking",
        "them in the tables. If a composition part is added after ingredients",
        "were entered, its values are empty and must be filled in before",
        "formulating."
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
          tags$tr(tags$td("min_inclusion"),
                  tags$td("Minimum inclusion rate in % of the mix (0-100); may be left empty"),
                  tags$td("no")),
          tags$tr(tags$td("max_inclusion"),
                  tags$td("Maximum inclusion rate in % of the mix (0-100); may be left empty"),
                  tags$td("no")),
          tags$tr(tags$td("category"), tags$td("Ingredient category"), tags$td("no"))
        )
      ),
      p(
        "Both comma-separated files (with a decimal point) and",
        "semicolon-separated files (with a decimal comma, as saved by Excel",
        "in many European locales) are accepted. A template CSV can be",
        "downloaded with the", tags$em("Download CSV template"), "button on",
        "the Import tab."
      )
    )
  )
}
