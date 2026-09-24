
<!-- README.md is generated from README.Rmd. Please edit that file -->

# feedR

### An RShiny app for linear feed formulation

FeedR calculates the inclusion rates of feed ingredients needed to reach
a targeted nutrient composition (protein, lipid, carbohydrate, ash and
gross energy). Under the hood, the formulation is solved as a linear
programming problem with
[lpSolve](https://cran.r-project.org/package=lpSolve), either

- minimising the deviation from the nutrient targets (default), or
- minimising the cost of the mix while meeting every nutrient target
  (least-cost formulation).

Every target can optionally be given a maximum; the target is then
treated as a minimum and the mix must lie within that range. If the
requirements cannot be met, the app explains which of them conflict.
Each ingredient can also be given a minimum and/or maximum inclusion
rate (% of the mix). After each calculation, a PDF report with all
inputs and the calculated formulation can be downloaded. The FAQ tab of
the app explains the mathematical model in detail.

### Tabs

| Tab        | Ingredients offered                                       |
|------------|-----------------------------------------------------------|
| Simplified | Ingredient categories with averaged nutrient values       |
| Full       | Individual ingredients of the feed ingredient database    |
| Import     | Your own ingredient list, uploaded as a CSV file          |
| Manual     | Own composition parts and ingredients, typed in by hand   |
| FAQ        | How the formulation works, how to enter costs, CSV format |

In the *Selected Ingredients* table only the cost and inclusion limit
(min./max. inclusion) columns can be edited; nutrient values are fixed.
On the Simplified and Full tabs this table does not repeat the nutrient
values, which are already shown in the *Available Ingredients* table
(they are still used for the formulation).

### CSV import format

One row per ingredient with the columns `ingredient`, `protein`,
`lipid`, `carbohydrate`, `ash` (all in %) and `energy` (MJ/kg). Optional
columns are `cost` (price per kg), `min_inclusion` / `max_inclusion`
(minimum / maximum inclusion rate in % of the mix) and `category`.
Comma- and semicolon-separated files are accepted. A template can be
downloaded on the Import tab (it is also in
`data/templates/ingredients_template.csv`).

### Running the app

``` r
install.packages(c("shiny", "lpSolve", "tidyverse", "DT", "gridExtra"))
shiny::runApp()  # from the repository root
```

### Logging

Everything that happens under the hood (data loading, user actions, the
linear programs that are built and their solutions) is logged to the R
console, e.g.

    14:03:12.345 [INFO ] [full] Formulate clicked: 3 ingredients, target matching
    14:03:12.350 [INFO ] [full] Solver status 0 (optimal solution found), objective = 16.38

The default level `DEBUG` also prints the full LP model and solver
output. Reduce the detail with `options(feedr.log_level = "INFO")` (or
`WARN`, `ERROR`) before starting the app, or set the environment
variable `FEEDR_LOG_LEVEL`.

### Testing

All helper functions are covered by a
[testthat](https://testthat.r-lib.org/) suite in `tests/testthat/`. Run
it from the repository root with

``` sh
Rscript tests/run_tests.R
```

or, in an R session started in the repository root,
`testthat::test_dir("tests/testthat")`. The script exits with a non-zero
status if a test fails. On GitHub, the workflow
`.github/workflows/tests.yaml` runs the suite on every push and pull
request.

| Test file                       | Covers                                                                                                                                              |
|---------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| `test-logging.R`                | log levels, message format, `log_object()`, `fmt_num()`, `fmt_num_each()`                                                                           |
| `test-parse_decimal.R`          | `parse_decimal()`                                                                                                                                   |
| `test-add_to_selection.R`       | `add_to_selection()`                                                                                                                                |
| `test-checks.R`                 | `check_bounds()`, `check_inclusion_limits()`, `validate_optional_value()`                                                                           |
| `test-formulate_feed.R`         | `formulate_feed()`: both modes, ranges, inclusion limits, the exact arguments passed to `lp()`, solver errors                                       |
| `test-diagnose_infeasibility.R` | `diagnose_infeasibility()`, `lp_status_text()`                                                                                                      |
| `test-format_solution.R`        | `format_solution()`, `inclusion_limit_notes()`                                                                                                      |
| `test-read_ingredient_csv.R`    | `read_ingredient_csv()` and the downloadable CSV template                                                                                           |
| `test-report.R`                 | report snapshot, report tables, PDF layout helpers, and the generated PDFs (their text is checked with `pdftotext` when poppler-utils is installed) |
| `test-ui_helpers.R`             | `column_titles()`, `target_input_row()`, nutrient and editing constants                                                                             |

`helper-load.R` loads the code without starting the app (and without the
ingredient database); `helper-fixtures.R` provides small ingredient
tables whose solutions can be checked by hand. To add tests, create
another `test-*.R` file in `tests/testthat/`.

### Code structure

    app.R                      entry point; sources all files in order
    dependencies.R             required packages
    code/
      logging.R                console logging helpers (log_info(), log_debug(), ...)
      data_prep.R              loads the ingredient database (feed_data, feed_data_summarised)
      helper_functions.R       LP formulation, selection handling, CSV import, output formatting
      report.R                 PDF report (drawn with grid/gridExtra, no LaTeX needed)
      ui.R / server.R          top-level UI and server combining the tabs
      modules/
        formulation.R          shared UI and server logic of all formulation tabs
        ui_summary.R, server_summary.R   "Simplified" tab
        ui_full.R, server_full.R         "Full" tab
        ui_import.R, server_import.R     "Import" tab
        ui_manual.R, server_manual.R     "Manual" tab
        ui_faq.R                         "FAQ" tab
    tests/
      run_tests.R              runs the test suite (used by CI)
      testthat/                helper-*.R (loading, fixtures) and test-*.R files
    .github/workflows/tests.yaml   runs the tests on GitHub
    data/                      feed ingredient composition database (CSV)
    data/templates/            CSV template offered on the Import tab
    www/style.css              custom styling

### How the code works

This section explains which helper functions are involved in each
scenario and how `formulate_feed()` turns its arguments into a call of
`lpSolve::lp()`. The examples below are run when this README is knitted,
so their output always reflects the current code.

#### The big picture

The scheme below shows how the functions work together, from the
ingredient data to the outputs. Boxes are functions or data, arrow
labels say what is passed along. Read it top to bottom:

1.  **Ingredient data** comes from the database (loaded once by
    `data_prep.R`) or from an uploaded CSV file.
2.  Each **tab module** provides its ingredient table. Simplified, Full
    and Import all hand it to the shared `setup_formulation()` (3a); the
    Manual tab keeps its own composition parts and ingredients (3b).
3.  Clicking **Formulate** runs the checks, then `formulate_feed()`
    builds the linear program and calls `lpSolve::lp()`; if there is no
    solution, `diagnose_infeasibility()` explains why.
4.  The **result** is shown as text in the *Solution* box and can be
    downloaded as a PDF report.

Every step writes to the console through the helpers in `code/logging.R`
(not drawn, to keep the scheme readable).

``` mermaid
flowchart TB
  subgraph SRC["1 · Ingredient data"]
    DB[("data/FICD 2025-10-27.csv")]
    FD["feed_data<br/>one row per ingredient"]
    FDS["feed_data_summarised<br/>mean per category"]
    CSV[/"uploaded CSV file"/]
    RIC["read_ingredient_csv()<br/>uses parse_decimal()"]
    DB -- "data_prep.R" --> FD
    FD -- "category means" --> FDS
    CSV --> RIC
  end

  subgraph TABS["2 · Tab modules"]
    SUM["server_summary()<br/>Simplified"]
    FULL["server_full()<br/>Full + category filter"]
    IMP["server_import()<br/>Import"]
    MAN["server_manual()<br/>Manual"]
  end
  FDS --> SUM
  FD --> FULL
  RIC --> IMP

  subgraph SF["3a · setup_formulation(): shared by Simplified, Full, Import"]
    AVT["Available Ingredients table"]
    ATS["add_to_selection()"]
    VAL["parse_decimal()<br/>validate_optional_value()"]
    SEL["selection<br/>name · nutrients · cost · min/max inclusion"]
    TGT["sidebar<br/>targets + optional maxima"]
    AVT -- "row clicked" --> ATS --> SEL
    VAL -- "cost / limit edited" --> SEL
  end
  SUM -- "available_data" --> AVT
  FULL -- "available_data" --> AVT
  IMP -- "available_data" --> AVT

  subgraph MS["3b · server_manual(): own state"]
    PARTS["composition parts<br/>key · name · target · maximum"]
    MING["ingredients<br/>typed row by row"]
  end
  MAN --> PARTS
  MAN --> MING

  subgraph FORM["4 · Formulate button"]
    CHK["check_bounds()<br/>check_inclusion_limits()"]
    FF["formulate_feed()"]
    LP[["lpSolve::lp()"]]
    DIAG["diagnose_infeasibility()<br/>extra small lp() calls"]
    RES["result<br/>inclusion · achieved · cost · diagnosis"]
  end
  SEL --> CHK
  TGT --> CHK
  PARTS --> CHK
  MING --> CHK
  CHK -- "inputs valid" --> FF
  FF -- "f.obj, f.con, f.dir, f.rhs" --> LP
  LP -- "status 0: solution" --> RES
  LP -- "status 2: infeasible" --> DIAG --> RES

  subgraph OUT["5 · Output"]
    FS["format_solution()<br/>inclusion_limit_notes()"]
    BOX["Solution box"]
    NR["new_formulation_report()<br/>snapshot of inputs + result"]
    WR["write_formulation_report()"]
    PDF[/"PDF report"/]
  end
  CHK -- "problems found: message" --> BOX
  RES --> FS --> BOX
  RES --> NR
  NR -- "Download PDF report" --> WR --> PDF
```

#### Helper functions at a glance

All pure (non-Shiny) helpers live in `code/helper_functions.R`, the
logging helpers in `code/logging.R`. The Shiny modules only collect
input, call these helpers and display their results.

| Function                                                                 | Purpose                                                                                                            | Called by                                                                                |
|--------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| `parse_decimal()`                                                        | Turns typed text into numbers (accepts `2.5` and `2,5`)                                                            | `read_ingredient_csv()`, table cell edits in `setup_formulation()` and `server_manual()` |
| `read_ingredient_csv()`                                                  | Reads and validates an uploaded ingredient CSV                                                                     | `server_import()`                                                                        |
| `add_to_selection()`                                                     | Appends clicked ingredients to the selection (columns: label, nutrients, `cost`, `min_inclusion`, `max_inclusion`) | `setup_formulation()`                                                                    |
| `validate_optional_value()`                                              | Checks an edited cost / inclusion limit (`code/modules/formulation.R`)                                             | `setup_formulation()`, `server_manual()`                                                 |
| `check_bounds()`                                                         | Before solving: every target present, no nutrient maximum below its minimum                                        | `setup_formulation()`, `server_manual()`                                                 |
| `check_inclusion_limits()`                                               | Before solving: limits within 0–100 %, min ≤ max, minimums sum ≤ 100 %                                             | `setup_formulation()`, `server_manual()`                                                 |
| `formulate_feed()`                                                       | Builds the linear program, calls `lp()`, reads the solution back                                                   | `setup_formulation()`, `server_manual()`                                                 |
| `diagnose_infeasibility()`                                               | Explains why no solution exists (runs its own small `lp()` calls)                                                  | `formulate_feed()`                                                                       |
| `lp_status_text()`                                                       | Human-readable lpSolve status code                                                                                 | `formulate_feed()`, `diagnose_infeasibility()`                                           |
| `format_solution()`                                                      | Turns the result into the text shown under *Solution*                                                              | `setup_formulation()`, `server_manual()`                                                 |
| `inclusion_limit_notes()`                                                | The `[min 2 %, max 60 %, max reached]` notes in the solution                                                       | `format_solution()`                                                                      |
| `new_formulation_report()`                                               | Snapshot of inputs and result for the PDF report (`code/report.R`)                                                 | `setup_formulation()`, `server_manual()`                                                 |
| `write_formulation_report()`                                             | Draws the PDF report (tables via `report_*_table()`, page layout via `draw_blocks()`)                              | `setup_report_download()`                                                                |
| `log_info()`, `log_debug()`, `log_warn()`, `log_error()`, `log_object()` | Console logging                                                                                                    | everywhere                                                                               |
| `fmt_num()`, `fmt_num_each()`                                            | Compact number formatting for messages                                                                             | everywhere                                                                               |

#### Which functions interact in which scenario

**1. Starting the app.** `app.R` sources the files in dependency order:

    dependencies.R          packages
    code/logging.R          log_*() helpers (needed by everything below)
    code/data_prep.R        reads data/FICD ... .csv -> feed_data, feed_data_summarised
    code/helper_functions.R
    code/modules/*.R        formulation.R (shared), then one ui_*/server_* pair per tab
    code/ui.R, server.R     ui_*() and server_*() called with the ids
                            "summary", "full", "import", "manual", "faq"

**2. Choosing ingredients on the Simplified, Full or Import tab.** The
three tabs share one implementation: each tab’s `server_*()` creates a
reactive table of available ingredients and passes it to
`setup_formulation()`.

    server_summary()  -> available_data = feed_data_summarised      (label column: category1)
    server_full()     -> available_data = feed_data filtered by category
    server_import()   -> available_data = read_ingredient_csv(upload)
                                |
                                v
    setup_formulation(input, output, session, available_data, label_col, ...)
      row clicked      -> add_to_selection(selection, picked rows, label_col)
      cell edited      -> parse_decimal() -> validate_optional_value()
                          -> selection$cost / $min_inclusion / $max_inclusion updated
      "Formulate"      -> scenario 4

**3. Entering everything by hand on the Manual tab.** `server_manual()`
keeps its own state: a table of composition parts (`key`, `name`,
`target`, `maximum`) and a table of ingredients with one column per part
key (`part1`, `part2`, …). Typed values are checked with
`parse_decimal()` and `validate_optional_value()`. When formulating, it
calls the same helpers as scenario 4, but passes its own parts instead
of the five built-in nutrients:

``` r
formulate_feed(ingredients,
               targets = c(part1 = 40, part2 = 10),      # from the parts table
               maxima  = c(part1 = 45, part2 = NA),
               nutrients = c("part1", "part2"),           # ingredient columns to use
               nutrient_labels = c("Protein (%)", "Lipid (%)"))
```

**4. Clicking “Formulate”.**

    setup_formulation() / server_manual()
      |- check_bounds(targets, maxima)                  problems -> shown, stop
      |- check_inclusion_limits(min, max)               problems -> shown, stop
      |- (least-cost only) all costs entered?           missing  -> shown, stop
      |- result <- formulate_feed(...)
      |     |- builds objective, constraint matrix, directions, right-hand sides
      |     |- lp("min", f.obj, f.con, f.dir, f.rhs)
      |     |- status 0 -> inclusion rates + achieved composition
      |     '- status 2 -> diagnose_infeasibility()      (scenario 5)
      |- format_solution(result)                         -> "Solution" box
      |     '- inclusion_limit_notes()
      '- new_formulation_report(result, ...)             -> "Download PDF report" button
            '- on download: write_formulation_report()

**5. No feasible solution.** `diagnose_infeasibility()` narrows down the
cause with small auxiliary linear programs (see below) and returns the
explanation that `format_solution()` prints instead of a mix.

#### From function arguments to `lpSolve::lp()`

`formulate_feed()` always makes exactly one call

``` r
lp("min", f.obj, f.con, f.dir, f.rhs)
```

whose arguments are the objective coefficients (`objective.in`), the
constraint matrix (`const.mat`, one row per constraint, one column per
variable), the constraint directions (`const.dir`) and the right-hand
sides (`const.rhs`). lpSolve implicitly requires every variable to be ≥
0, which is exactly the non-negativity of inclusion rates and
deviations.

The scheme shows which argument of `formulate_feed()` ends up in which
part of the linear program, and how the result is read back (dotted
arrow: a nutrient without a maximum gets a target row instead of range
rows). The tables below give the details.

``` mermaid
flowchart LR
  subgraph IN["Arguments of formulate_feed()"]
    ING["ingredients[, nutrients]"]
    TG["targets"]
    MX["maxima"]
    LIM["ingredients$min_inclusion<br/>ingredients$max_inclusion"]
    CO["ingredients$cost"]
    LC["least_cost"]
  end

  subgraph BUILD["Building the linear program"]
    A["A = t(ingredients[, nutrients])<br/>nutrients × ingredients"]
    R1["nutrient target rows<br/>A[j, ] &gt;= target  (least cost)<br/>A[j, ] + under - over = target  (target matching)"]
    R2["range rows<br/>A[j, ] &gt;= target<br/>A[j, ] &lt;= maximum"]
    R3["inclusion limit rows<br/>x[i] &gt;= min / 100<br/>x[i] &lt;= max / 100"]
    R4["mass balance<br/>sum(x) = 1"]
    OBJ["objective<br/>costs (least cost) or<br/>1 per under/over deviation"]
  end
  ING --> A
  A --> R1
  A --> R2
  TG --> R1
  TG --> R2
  MX -- "maximum set" --> R2
  MX -. "no maximum" .-> R1
  LIM --> R3
  CO --> OBJ
  LC -- "chooses model" --> OBJ

  R1 --> CON["f.con · f.dir · f.rhs<br/>rows stacked with rbind()"]
  R2 --> CON
  R3 --> CON
  R4 --> CON
  OBJ --> FOBJ["f.obj"]
  CON --> LP[["lp(&quot;min&quot;, f.obj, f.con, f.dir, f.rhs)"]]
  FOBJ --> LP

  subgraph RES["Result of formulate_feed()"]
    INC["inclusion = solution[1:n]"]
    ACH["achieved = A %*% inclusion"]
    ST["feasible = status == 0<br/>objective = objval"]
  end
  LP --> INC
  LP --> ST
  INC --> ACH
```

**Variables (columns of `f.con`).** The first *n* variables are always
the inclusion rates *x<sub>i</sub>* of the *n* ingredients, as fractions
of the mix (so 0.25 = 25 %), in the row order of `ingredients`. In
target-matching mode they are followed by two deviation variables per
nutrient *without* a maximum: first all `under[...]` (shortfall), then
all `over[...]` (excess).

**How the arguments of `formulate_feed()` are used:**

| Argument of `formulate_feed()`                | Ends up in                                                                                                                                   |
|-----------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `ingredients[, nutrients]`                    | transposed into the nutrient matrix `A` (nutrients × ingredients), whose rows become constraint rows of `f.con`                              |
| `targets`                                     | `f.rhs` of the nutrient rows (target, or minimum when a maximum is set)                                                                      |
| `maxima`                                      | nutrients with a maximum get an extra `<=` row with the maximum as `f.rhs`; in target-matching mode they also lose their deviation variables |
| `least_cost`                                  | chooses the objective `f.obj` and whether nutrient rows are `>=` (least cost) or `=` with deviations (target matching)                       |
| `ingredients$cost`                            | `f.obj` in least-cost mode (unused otherwise, except for reporting the mix cost)                                                             |
| `ingredients$min_inclusion`, `$max_inclusion` | one row per limit with a single `1` in the ingredient’s column, direction `>=` / `<=`, `f.rhs` = limit / 100                                 |
| `nutrients`, `nutrient_labels`                | which columns of `ingredients` are used, and the names in logs and output                                                                    |
| `label_col`                                   | names of the ingredients in logs and in the result                                                                                           |

**Rows of `f.con`, in order:**

| Block            | Rows                               | Coefficients in the *x* columns                                            | `f.dir`                                    | `f.rhs`                                            | Present when            |
|------------------|------------------------------------|----------------------------------------------------------------------------|--------------------------------------------|----------------------------------------------------|-------------------------|
| Nutrient targets | one per nutrient without a maximum | `A[j, ]` (plus `+1` for `under[j]`, `-1` for `over[j]` in target matching) | `>=` (least cost) or `=` (target matching) | `targets[j]`                                       | nutrient has no maximum |
| Nutrient ranges  | two per nutrient with a maximum    | `A[j, ]`                                                                   | `>=`, then `<=`                            | `targets[j]`, then `maxima[j]`                     | nutrient has a maximum  |
| Inclusion limits | one per limit                      | `1` in column *i*, `0` elsewhere                                           | `>=` (min), `<=` (max)                     | `min_inclusion[i] / 100`, `max_inclusion[i] / 100` | ingredient has a limit  |
| Mass balance     | one                                | `1` for every ingredient                                                   | `=`                                        | `1`                                                | always                  |

All rows except the nutrient targets get zeros in the deviation columns.

**Objective `f.obj`:**

- least cost: `ingredients$cost` (cost of the mix per kg),
- target matching: `0` for every *x<sub>i</sub>* and `1` for every
  deviation variable, i.e. the sum of all absolute deviations from the
  targets.

**Reading the result back.** From the list returned by `lp()`,
`formulate_feed()` uses `status` (0 = optimal, 2 = infeasible; errors
are caught and reported), `solution[1:n]` (the inclusion rates, named by
`label_col`) and `objval`. The achieved composition is computed as
`A %*% inclusion`.

#### Worked example: least-cost formulation

Three ingredients, protein must lie between 38 and 42 % (target plus
maximum), the other nutrients are minimums, soybean meal is limited to
at most 60 % and fish oil must make up at least 2 % of the mix. At log
level `DEBUG`, `formulate_feed()` prints the nutrient matrix `A` and the
complete linear program: the row `objective` is `f.obj`, the other rows
are `f.con`, and the columns `dir` and `rhs` are `f.dir` and `f.rhs`.

``` r
ingredients <- data.frame(
  ingredient    = c("Fish meal", "Soybean meal", "Fish oil"),
  protein       = c(65, 46, 0),
  lipid         = c(9, 2, 99),
  carbohydrate  = c(2, 35, 0),
  ash           = c(16, 7, 0),
  energy        = c(19, 17.5, 38),
  cost          = c(1.8, 0.6, 2.2),
  min_inclusion = c(NA, NA, 2),
  max_inclusion = c(NA, 60, NA)
)
targets <- c(protein = 38, lipid = 8, carbohydrate = 15, ash = 8, energy = 18)
maxima  <- c(protein = 42, lipid = NA, carbohydrate = NA, ash = NA, energy = NA)
```

``` r
result <- formulate_feed(ingredients, targets, maxima, least_cost = TRUE)
#> [INFO ] [lp] Building LP (least_cost): 3 ingredients, 5 nutrients, 1 with min-max range
#> [DEBUG] [lp] Nutrient matrix A (nutrients x ingredients):
#>                      Fish meal Soybean meal Fish oil
#>     Protein (%)             65         46.0        0
#>     Lipid (%)                9          2.0       99
#>     Carbohydrate (%)         2         35.0        0
#>     Ash (%)                 16          7.0        0
#>     Energy (MJ/kg)          19         17.5       38
#> [INFO ] [lp] Inclusion limits: Fish oil >= 2 %; Soybean meal <= 60 %
#> [DEBUG] [lp] LP model (objective: minimise):
#>                                  Fish meal Soybean meal Fish oil dir   rhs
#>     objective                          1.8          0.6      2.2        NA
#>     Lipid (%) (min)                    9.0          2.0     99.0  >=  8.00
#>     Carbohydrate (%) (min)             2.0         35.0      0.0  >= 15.00
#>     Ash (%) (min)                     16.0          7.0      0.0  >=  8.00
#>     Energy (MJ/kg) (min)              19.0         17.5     38.0  >= 18.00
#>     Protein (%) (min)                 65.0         46.0      0.0  >= 38.00
#>     Protein (%) (max)                 65.0         46.0      0.0  <= 42.00
#>     Min inclusion [Fish oil]           0.0          0.0      1.0  >=  0.02
#>     Max inclusion [Soybean meal]       0.0          1.0      0.0  <=  0.60
#>     Sum of inclusion rates             1.0          1.0      1.0   =  1.00
#> [INFO ] [lp] Solver status 0 (optimal solution found), objective = 1.229
#> [DEBUG] [lp] Inclusion rates (fraction of the mix):
#>        Fish meal Soybean meal     Fish oil 
#>         0.263345     0.540925     0.195730
#> [DEBUG] [lp] Achieved composition:
#>          Protein (%)        Lipid (%) Carbohydrate (%)          Ash (%)   Energy (MJ/kg) 
#>              42.0000          22.8292          19.4591           8.0000          21.9075
```

``` r
cat(format_solution(result), sep = "\n")
#> Optimal least-cost feed mix:
#>   Soybean meal  54.09 %   ( 54.09 kg per 100 kg)   [max 60 %]
#>   Fish meal     26.33 %   ( 26.33 kg per 100 kg)
#>   Fish oil      19.57 %   ( 19.57 kg per 100 kg)   [min 2 %]
#> 
#> Nutrient composition of the mix:
#>                      Target/Min    Maximum   Achieved Difference
#>   Protein (%)             38.00      42.00      42.00   in range
#>   Lipid (%)                8.00          -      22.83      14.83
#>   Carbohydrate (%)        15.00          -      19.46       4.46
#>   Ash (%)                  8.00          -       8.00       0.00
#>   Energy (MJ/kg)          18.00          -      21.91       3.91
#> 
#> Cost of the mix: 1.23 per kg (122.92 per 100 kg)
```

The same linear program written out by hand gives the same solution,
which shows exactly what `formulate_feed()` passes to `lp()`:

``` r
A <- t(as.matrix(ingredients[, NUTRIENTS]))  # nutrients x ingredients

f.obj <- ingredients$cost
f.con <- rbind(
  A[c("lipid", "carbohydrate", "ash", "energy"), ],  # nutrient minimums
  A["protein", ], A["protein", ],                    # protein range
  c(0, 0, 1),                                        # fish oil >= 2 %
  c(0, 1, 0),                                        # soybean meal <= 60 %
  c(1, 1, 1)                                         # mass balance
)
f.dir <- c(">=", ">=", ">=", ">=", ">=", "<=", ">=", "<=", "=")
f.rhs <- c(8, 15, 8, 18, 38, 42, 0.02, 0.60, 1)

by_hand <- lp("min", f.obj, f.con, f.dir, f.rhs)
all.equal(by_hand$solution, unname(result$inclusion))
#> [1] TRUE
```

#### Worked example: target matching

With `least_cost = FALSE` the same data gives a larger program: the
nutrients without a maximum get `under[...]` and `over[...]` columns
with objective coefficient 1, and their rows become equalities
`A[j, ] %*% x + under[j] - over[j] = target[j]`. Protein, which has a
maximum, keeps its two range rows and has no deviation variables.

``` r
result <- formulate_feed(ingredients, targets, maxima, least_cost = FALSE)
#> [INFO ] [lp] Building LP (target_matching): 3 ingredients, 5 nutrients, 1 with min-max range
#> [DEBUG] [lp] Nutrient matrix A (nutrients x ingredients):
#>                      Fish meal Soybean meal Fish oil
#>     Protein (%)             65         46.0        0
#>     Lipid (%)                9          2.0       99
#>     Carbohydrate (%)         2         35.0        0
#>     Ash (%)                 16          7.0        0
#>     Energy (MJ/kg)          19         17.5       38
#> [INFO ] [lp] Inclusion limits: Fish oil >= 2 %; Soybean meal <= 60 %
#> [DEBUG] [lp] LP model (objective: minimise):
#>                                  Fish meal Soybean meal Fish oil under[Lipid (%)] under[Carbohydrate (%)] under[Ash (%)] under[Energy (MJ/kg)] over[Lipid (%)] over[Carbohydrate (%)] over[Ash (%)] over[Energy (MJ/kg)] dir   rhs
#>     objective                            0          0.0        0                1                       1              1                     1               1                      1             1                    1        NA
#>     Lipid (%) (target)                   9          2.0       99                1                       0              0                     0              -1                      0             0                    0   =  8.00
#>     Carbohydrate (%) (target)            2         35.0        0                0                       1              0                     0               0                     -1             0                    0   = 15.00
#>     Ash (%) (target)                    16          7.0        0                0                       0              1                     0               0                      0            -1                    0   =  8.00
#>     Energy (MJ/kg) (target)             19         17.5       38                0                       0              0                     1               0                      0             0                   -1   = 18.00
#>     Protein (%) (min)                   65         46.0        0                0                       0              0                     0               0                      0             0                    0  >= 38.00
#>     Protein (%) (max)                   65         46.0        0                0                       0              0                     0               0                      0             0                    0  <= 42.00
#>     Min inclusion [Fish oil]             0          0.0        1                0                       0              0                     0               0                      0             0                    0  >=  0.02
#>     Max inclusion [Soybean meal]         0          1.0        0                0                       0              0                     0               0                      0             0                    0  <=  0.60
#>     Sum of inclusion rates               1          1.0        1                0                       0              0                     0               0                      0             0                    0   =  1.00
#> [INFO ] [lp] Solver status 0 (optimal solution found), objective = 23.05
#> [DEBUG] [lp] Inclusion rates (fraction of the mix):
#>        Fish meal Soybean meal     Fish oil 
#>         0.221538     0.600000     0.178462
#> [DEBUG] [lp] Achieved composition:
#>          Protein (%)        Lipid (%) Carbohydrate (%)          Ash (%)   Energy (MJ/kg) 
#>              42.0000          20.8615          21.4431           7.7446          21.4908
cat(format_solution(result), sep = "\n")
#> Optimal feed mix (minimising deviation from nutrient targets):
#>   Soybean meal  60.00 %   ( 60.00 kg per 100 kg)   [max 60 %, max reached]
#>   Fish meal     22.15 %   ( 22.15 kg per 100 kg)
#>   Fish oil      17.85 %   ( 17.85 kg per 100 kg)   [min 2 %]
#> 
#> Nutrient composition of the mix:
#>                      Target/Min    Maximum   Achieved Difference
#>   Protein (%)             38.00      42.00      42.00   in range
#>   Lipid (%)                8.00          -      20.86      12.86
#>   Carbohydrate (%)        15.00          -      21.44       6.44
#>   Ash (%)                  8.00          -       7.74      -0.26
#>   Energy (MJ/kg)          18.00          -      21.49       3.49
#> 
#> Total absolute deviation from targets: 23.05
#> Cost of the mix: 1.15 per kg (115.14 per 100 kg)
```

#### When no solution exists

If `lp()` reports status 2, `formulate_feed()` calls
`diagnose_infeasibility()`, which runs its own small programs through
the internal helper `solve_mix()`. Each is again an `lp()` call over the
inclusion rates with the mass balance and the inclusion limits
(`rbind(extra rows, 1, diag(n), diag(n))` with directions `=`, `>=`
(minimums), `<=` (maximums)):

1.  no `lp()` call: are the maximum inclusion rates at least 100 % in
    total, and the minimums at most 100 %?
2.  for every hard nutrient requirement, `lp("min", A[j, ], ...)` and
    `lp("max", A[j, ], ...)` give the lowest and highest content any
    allowed mix can reach; a requirement outside that range is
    impossible on its own;
3.  otherwise, every pair of requirements is tested with
    `lp("min", rep(0, n), <the two requirements>, ...)` (a pure
    feasibility check) to find combinations that cannot be met together.

Raising the carbohydrate minimum to 20 % makes the example infeasible.
Each requirement is reachable on its own and every pair is compatible,
so the diagnosis falls through to its final message:

``` r
targets["carbohydrate"] <- 20
result <- formulate_feed(ingredients, targets, maxima, least_cost = TRUE)
#> [INFO ] [lp] Building LP (least_cost): 3 ingredients, 5 nutrients, 1 with min-max range
#> [DEBUG] [lp] Nutrient matrix A (nutrients x ingredients):
#>                      Fish meal Soybean meal Fish oil
#>     Protein (%)             65         46.0        0
#>     Lipid (%)                9          2.0       99
#>     Carbohydrate (%)         2         35.0        0
#>     Ash (%)                 16          7.0        0
#>     Energy (MJ/kg)          19         17.5       38
#> [INFO ] [lp] Inclusion limits: Fish oil >= 2 %; Soybean meal <= 60 %
#> [DEBUG] [lp] LP model (objective: minimise):
#>                                  Fish meal Soybean meal Fish oil dir   rhs
#>     objective                          1.8          0.6      2.2        NA
#>     Lipid (%) (min)                    9.0          2.0     99.0  >=  8.00
#>     Carbohydrate (%) (min)             2.0         35.0      0.0  >= 20.00
#>     Ash (%) (min)                     16.0          7.0      0.0  >=  8.00
#>     Energy (MJ/kg) (min)              19.0         17.5     38.0  >= 18.00
#>     Protein (%) (min)                 65.0         46.0      0.0  >= 38.00
#>     Protein (%) (max)                 65.0         46.0      0.0  <= 42.00
#>     Min inclusion [Fish oil]           0.0          0.0      1.0  >=  0.02
#>     Max inclusion [Soybean meal]       0.0          1.0      0.0  <=  0.60
#>     Sum of inclusion rates             1.0          1.0      1.0   =  1.00
#> [INFO ] [lp] Solver status 2 (infeasible), objective = 0
#> [DEBUG] [lp] Reachable range of Protein (%): 0 to 63.7
#> [DEBUG] [lp] Reachable range of Lipid (%): 6.6 to 99
#> [DEBUG] [lp] Reachable range of Carbohydrate (%): 0 to 21.76
#> [DEBUG] [lp] Reachable range of Ash (%): 0 to 15.68
#> [DEBUG] [lp] Reachable range of Energy (MJ/kg): 18.48 to 38
#> [DEBUG] [lp] Feasibility check Protein (%) + Lipid (%): optimal solution found
#> [DEBUG] [lp] Feasibility check Protein (%) + Carbohydrate (%): optimal solution found
#> [DEBUG] [lp] Feasibility check Protein (%) + Ash (%): optimal solution found
#> [DEBUG] [lp] Feasibility check Protein (%) + Energy (MJ/kg): optimal solution found
#> [DEBUG] [lp] Feasibility check Lipid (%) + Carbohydrate (%): optimal solution found
#> [DEBUG] [lp] Feasibility check Lipid (%) + Ash (%): optimal solution found
#> [DEBUG] [lp] Feasibility check Lipid (%) + Energy (MJ/kg): optimal solution found
#> [DEBUG] [lp] Feasibility check Carbohydrate (%) + Ash (%): optimal solution found
#> [DEBUG] [lp] Feasibility check Carbohydrate (%) + Energy (MJ/kg): optimal solution found
#> [DEBUG] [lp] Feasibility check Ash (%) + Energy (MJ/kg): optimal solution found
#> [WARN ] [lp] No feasible solution. Each requirement can be met on its own, but not all of them at the same time. Widen the minimum-maximum ranges, relax the inclusion limits or select additional ingredients.
cat(format_solution(result), sep = "\n")
#> No feasible solution found.
#> 
#> Each requirement can be met on its own, but not all of them at the same time.
#> Widen the minimum-maximum ranges, relax the inclusion limits or select additional ingredients.
```

### Data sources

| Dataset                     | Source | Version |
|-----------------------------|--------|---------|
| Feed ingredient composition | IAFFD  |         |
| Nutrient requirement        | IAFFD  |         |
