# Tests for the PDF report (code/report.R)

# A feasible least-cost report on the three-ingredient fixture
make_report <- function(targets = nutrient_vector(38, 8, 15, 8, 18), least_cost = TRUE,
                        tab = "Full", data_source = "test data") {
  ingredients <- make_ingredients(min_inclusion = c(NA, NA, 2), max_inclusion = c(NA, 60, NA))
  result <- formulate_feed(ingredients, targets, nutrient_vector(protein = 42),
                           least_cost = least_cost)
  new_formulation_report(result, ingredients, "ingredient", tab, data_source)
}

# Text of a PDF file (NULL if pdftotext is not installed)
pdf_text_content <- function(path) {
  skip_if(Sys.which("pdftotext") == "", "pdftotext (poppler-utils) is not installed")
  paste(system2("pdftotext", c("-layout", shQuote(path), "-"), stdout = TRUE), collapse = "\n")
}


# Snapshot ------------------------------------------------------------------------

test_that("new_formulation_report() snapshots inputs and result", {
  report <- make_report()

  expect_s3_class(report, "formulation_report")
  expect_equal(report$tab, "Full")
  expect_equal(report$data_source, "test data")
  expect_true(report$result$feasible)
  expect_equal(names(report$ingredients),
               c("label", NUTRIENTS, "cost", "min_inclusion", "max_inclusion"))
  expect_equal(report$label_title, "Ingredient")
  expect_equal(report$nutrient_labels, unname(NUTRIENT_LABELS))
})

test_that("missing optional columns become NA and category labels are titled", {
  ingredients <- data.frame(category1 = c("fish", "plant"), p1 = c(60, 20))
  result <- formulate_feed(ingredients, c(p1 = 40), label_col = "category1",
                           nutrients = "p1", nutrient_labels = "P1")
  report <- new_formulation_report(result, ingredients, "category1", "Simplified",
                                   nutrients = "p1", nutrient_labels = "P1")

  expect_true(all(is.na(report$ingredients[, c("cost", "min_inclusion", "max_inclusion")])))
  expect_equal(report$label_title, "Category")
  expect_null(report$data_source)
})

test_that("report_file_name() contains tab and timestamp", {
  report <- make_report()
  report$created <- as.POSIXct("2026-09-24 14:05:00")
  expect_equal(report_file_name(report), "feedR_report_full_2026-09-24_1405.pdf")
})


# Tables --------------------------------------------------------------------------

test_that("the mix table lists all ingredients by inclusion, with limits and a total", {
  table <- report_mix_table(make_report())

  expect_equal(names(table), c("Ingredient", "Inclusion (%)", "Cost share (per kg)", "Inclusion limits"))
  expect_equal(table$Ingredient, c("Soybean meal", "Fish meal", "Fish oil", "Total"))
  expect_equal(table$`Inclusion (%)`, c("54.09", "26.33", "19.57", "100.00"))
  expect_equal(table$`Inclusion limits`, c("max 60 %", "-", "min 2 %", ""))
  expect_equal(table$`Cost share (per kg)`[4], "1.229")
})

test_that("the nutrient table shows achieved values only for a feasible result", {
  feasible <- report_nutrient_table(make_report())
  expect_equal(names(feasible), c("Nutrient", "Target / minimum", "Maximum", "Achieved", "Difference"))
  expect_equal(feasible$Maximum[1], "42.00")
  expect_equal(feasible$Difference[1], "in range")
  expect_equal(feasible$Maximum[2], "-")

  infeasible <- report_nutrient_table(make_report(targets = nutrient_vector(38, 8, 20, 8, 18)))
  expect_equal(names(infeasible), c("Nutrient", "Target / minimum", "Maximum"))
})

test_that("the ingredient table shows all inputs with display names", {
  table <- report_ingredient_table(make_report())
  expect_equal(names(table), c("Ingredient", unname(NUTRIENT_LABELS), "Cost (per kg)",
                               "Min. incl. (%)", "Max. incl. (%)"))
  expect_equal(table$`Protein (%)`, c("65.00", "46.00", "0.00"))
  expect_equal(table$`Max. incl. (%)`, c("-", "60.00", "-"))
})

test_that("summary lines describe tab, data, mode and result", {
  lines <- report_summary_lines(make_report())
  expect_equal(lines[1:3], c("Tab: Full", "Ingredient data: test data",
                             "Mode: Least-cost formulation (cheapest mix meeting all minimums and ranges)"))
  expect_true("Result: optimal solution found." %in% lines)
  expect_true(any(grepl("^Cost of the mix: 1.229 per kg", lines)))

  goal <- report_summary_lines(make_report(least_cost = FALSE))
  expect_true(any(grepl("^Total absolute deviation from targets:", goal)))
})


# Layout helpers ------------------------------------------------------------------

test_that("pdf_text() turns hyphens into printable hyphens but keeps minus signs", {
  expect_equal(pdf_text(c("2026-09-24", "-1.71", "non-dehulled", "  - item", "(-5)")),
               c("2026­09­24", "-1.71", "non­dehulled", "  - item", "(-5)"))
})

test_that("split_table() splits long tables into parts", {
  parts <- split_table(data.frame(x = 1:60), rows = 28)
  expect_equal(vapply(parts, nrow, 1L), c(28L, 28L, 4L))
  expect_length(split_table(data.frame(x = 1:3)), 1)
})

test_that("grob_size() measures tables by their columns and rows", {
  withr::local_pdf(NULL)
  grid.newpage()
  table <- table_grob(data.frame(a = c("x", "y"), b = c("1", "2")), max_width = 7)
  size <- grob_size(table)
  expect_gt(size[["width"]], 0.3)
  expect_gt(size[["height"]], 0.3)
})

test_that("wide tables are drawn with a smaller font to fit the page", {
  withr::local_pdf(NULL)
  grid.newpage()
  wide <- as.data.frame(matrix("123456.78", nrow = 2, ncol = 14))
  expect_lte(grob_size(table_grob(wide, max_width = 6.87))[["width"]],
             grob_size(table_grob(wide, max_width = 100))[["width"]])
})


# PDF files -----------------------------------------------------------------------

test_that("write_formulation_report() writes a one-page PDF for a small formulation", {
  path <- withr::local_tempfile(fileext = ".pdf")
  pages <- write_formulation_report(path, make_report())

  expect_equal(pages, 1)
  expect_equal(readBin(path, "raw", 5), charToRaw("%PDF-"))

  text <- pdf_text_content(path)
  expect_match(text, "FeedR: Feed Formulation Report")
  expect_match(text, "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2} \\| page 1")  # footer date with hyphens
  expect_match(text, "Calculated feed formulation")
  expect_match(text, "Soybean meal +54.09")
  expect_match(text, "Protein \\(%\\) +38.00 +42.00 +42.00 +in range")
  expect_match(text, "Ingredient inputs")
  expect_match(text, "page 1")
})

test_that("an infeasible report explains why instead of listing a mix", {
  path <- withr::local_tempfile(fileext = ".pdf")
  write_formulation_report(path, make_report(targets = nutrient_vector(38, 8, 20, 8, 18)))

  text <- pdf_text_content(path)
  expect_match(text, "Why no solution was found")
  expect_match(text, "Nutrient targets")
  expect_no_match(text, "Calculated feed formulation")
})

test_that("many ingredients are spread over several pages", {
  n <- 80
  ingredients <- data.frame(ingredient = sprintf("Ingredient %02d", seq_len(n)),
                            p1 = seq(1, 100, length.out = n), cost = 1)
  result <- formulate_feed(ingredients, c(p1 = 40), nutrients = "p1", nutrient_labels = "P1")
  report <- new_formulation_report(result, ingredients, "ingredient", "Manual",
                                   nutrients = "p1", nutrient_labels = "P1")
  path <- withr::local_tempfile(fileext = ".pdf")

  pages <- write_formulation_report(path, report)
  expect_gt(pages, 1)

  text <- pdf_text_content(path)
  expect_match(text, sprintf("page %d", pages))
  expect_match(text, "Ingredient 80")
})
