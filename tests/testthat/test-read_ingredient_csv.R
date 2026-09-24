# Tests for read_ingredient_csv() and the CSV template (code/helper_functions.R)

header <- "ingredient,protein,lipid,carbohydrate,ash,energy"

test_that("a comma-separated file is read with the required columns", {
  path <- local_csv(c(header, "A,60,10,5,15,20", "B,30.5,5,50,5,17"))
  data <- read_ingredient_csv(path)

  expect_s3_class(data, "data.frame")
  expect_equal(names(data), c("ingredient", NUTRIENTS))
  expect_equal(data$ingredient, c("A", "B"))
  expect_equal(data$protein, c(60, 30.5))
})

test_that("semicolon-separated files with decimal commas are accepted", {
  path <- local_csv(c("ingredient;protein;lipid;carbohydrate;ash;energy;cost",
                      "A;60,5;10;5;15;20;1,2"))
  data <- read_ingredient_csv(path)
  expect_equal(data$protein, 60.5)
  expect_equal(data$cost, 1.2)
})

test_that("column names are case-insensitive, 'category' is renamed and others ignored", {
  path <- local_csv(c("Category,Ingredient,Protein,LIPID,Carbohydrate,Ash,Energy,Notes",
                      "fish,A,60,10,5,15,20,some note"))
  data <- read_ingredient_csv(path)
  expect_equal(names(data), c("category1", "ingredient", NUTRIENTS))
  expect_equal(data$category1, "fish")
})

test_that("optional cost and inclusion limits may be empty", {
  path <- local_csv(c(paste0(header, ",cost,min_inclusion,max_inclusion"),
                      "A,60,10,5,15,20,1.5,10,30.5",
                      "B,30,5,50,5,17,,,"))
  data <- read_ingredient_csv(path)
  expect_equal(data$cost, c(1.5, NA))
  expect_equal(data$min_inclusion, c(10, NA))
  expect_equal(data$max_inclusion, c(30.5, NA))
})

test_that("ingredient names are trimmed", {
  path <- local_csv(c(header, "  A  ,60,10,5,15,20"))
  expect_equal(read_ingredient_csv(path)$ingredient, "A")
})

test_that("missing required columns are reported", {
  path <- local_csv(c("ingredient,protein,lipid", "A,1,2"))
  expect_error(read_ingredient_csv(path),
               "missing the required column\\(s\\): carbohydrate, ash, energy", class = "simpleError")
})

test_that("files without ingredients are rejected", {
  expect_error(read_ingredient_csv(local_csv(header)), "does not contain any ingredients")
})

test_that("empty and duplicated ingredient names are rejected", {
  expect_error(read_ingredient_csv(local_csv(c(header, ",60,10,5,15,20"))),
               "non-empty 'ingredient' name")
  expect_error(read_ingredient_csv(local_csv(c(header, "A,60,10,5,15,20", "A,1,1,1,1,1"))),
               "must be unique. Duplicated: A")
})

test_that("non-numeric nutrient values are reported with their rows", {
  path <- local_csv(c(header, "A,60,10,5,15,20", "B,x,10,5,15,20", "C,,10,5,15,20"))
  expect_error(read_ingredient_csv(path),
               "Column 'protein' must contain a number in every row. Problem in row\\(s\\): 2, 3.")
})

test_that("invalid costs and inclusion limits are reported", {
  expect_error(
    read_ingredient_csv(local_csv(c(paste0(header, ",cost"), "A,60,10,5,15,20,-1"))),
    "Column 'cost' must be empty or a non-negative number. Problem in row\\(s\\): 1."
  )
  expect_error(
    read_ingredient_csv(local_csv(c(paste0(header, ",max_inclusion"), "A,60,10,5,15,20,101"))),
    "Column 'max_inclusion' must be empty or a number between 0 and 100"
  )
  expect_error(
    read_ingredient_csv(local_csv(c(paste0(header, ",min_inclusion"), "A,60,10,5,15,20,abc"))),
    "Column 'min_inclusion' must be empty or a number between 0 and 100"
  )
})

test_that("the downloadable template is a valid import file", {
  data <- read_ingredient_csv(file.path(app_root, INGREDIENT_TEMPLATE))
  expect_gt(nrow(data), 0)
  expect_true(all(c("ingredient", NUTRIENTS, "cost", "min_inclusion", "max_inclusion") %in%
                    names(data)))
})
