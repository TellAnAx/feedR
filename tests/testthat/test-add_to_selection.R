# Tests for add_to_selection() (code/helper_functions.R)

test_that("the first selection keeps label, nutrients and adds empty cost and limits", {
  picked <- make_ingredients()[1:2, c("ingredient", NUTRIENTS)]
  selection <- add_to_selection(NULL, picked, "ingredient")

  expect_equal(names(selection),
               c("ingredient", NUTRIENTS, "cost", "min_inclusion", "max_inclusion"))
  expect_equal(selection$ingredient, c("Fish meal", "Soybean meal"))
  expect_true(all(is.na(selection[, c("cost", "min_inclusion", "max_inclusion")])))
})

test_that("cost and inclusion limits of the picked rows are used as initial values", {
  picked <- make_ingredients(cost = c(1, 2, 3), min_inclusion = c(5, NA, NA),
                             max_inclusion = c(NA, 60, NA))
  selection <- add_to_selection(NULL, picked, "ingredient")

  expect_equal(selection$cost, c(1, 2, 3))
  expect_equal(selection$min_inclusion, c(5, NA, NA))
  expect_equal(selection$max_inclusion, c(NA, 60, NA))
})

test_that("already selected ingredients are not added twice and keep their values", {
  first <- add_to_selection(NULL, make_ingredients()[1:2, ], "ingredient")
  first$cost[1] <- 99  # entered by the user

  second <- add_to_selection(first, make_ingredients()[c(1, 3), ], "ingredient")

  expect_equal(second$ingredient, c("Fish meal", "Soybean meal", "Fish oil"))
  expect_equal(second$cost[1], 99)
  expect_equal(rownames(second), c("1", "2", "3"))
})

test_that("other label columns work, e.g. category1 on the Simplified tab", {
  picked <- data.frame(category1 = c("fish", "oil"), protein = 1, lipid = 2,
                       carbohydrate = 3, ash = 4, energy = 5)
  selection <- add_to_selection(NULL, picked, "category1")
  expect_equal(selection$category1, c("fish", "oil"))
})

test_that("picking nothing new returns the selection unchanged", {
  first <- add_to_selection(NULL, make_ingredients(), "ingredient")
  expect_equal(add_to_selection(first, make_ingredients()[1, ], "ingredient"), first)
})
