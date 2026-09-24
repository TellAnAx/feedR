# Tests for the non-reactive helpers and constants of the shared formulation
# module (code/modules/formulation.R) and the nutrient constants
# (code/helper_functions.R)

test_that("nutrient constants are consistent", {
  expect_equal(NUTRIENTS, c("protein", "lipid", "carbohydrate", "ash", "energy"))
  expect_named(NUTRIENT_LABELS, NUTRIENTS)
  expect_setequal(names(TARGET_INPUT_PREFIX), NUTRIENTS)
})

test_that("only cost and inclusion limits are editable in the selection table", {
  expect_equal(EDITABLE_SELECTION_COLUMNS, c("cost", "min_inclusion", "max_inclusion"))
})

test_that("column_titles() maps column names to headers", {
  expect_equal(
    column_titles(c("ingredient", "protein", "energy", "cost", "min_inclusion",
                    "max_inclusion", "category1", "other"), "ingredient", "Ingredient"),
    c("Ingredient", "Protein (%)", "Energy (MJ/kg)", "Cost (per kg)", "Min. inclusion (%)",
      "Max. inclusion (%)", "Category", "other")
  )
  expect_equal(column_titles(c("category1", "cost"), "category1", "Category"),
               c("Category", "Cost (per kg)"))
})

test_that("target_input_row() creates namespaced target and maximum inputs", {
  html <- as.character(target_input_row(NS("full"), "lipid", "Fat (%)", 5))
  expect_match(html, 'id="full-fat_req"')
  expect_match(html, 'id="full-fat_max"')
  expect_match(html, "Fat \\(%\\)")
  expect_match(html, 'value="5"')
})
