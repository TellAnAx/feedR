# =============================================================================
# data_prep.R - load and prepare the feed ingredient data
#
# Creates two global data frames that are used by the tab modules:
#
#   feed_data            - one row per ingredient of the IAFFD Feed Ingredient
#                          Composition Database (FICD) export in data/.
#                          Columns: category1, category2, ingredient, protein,
#                          lipid, carbohydrate, ash (all in %), energy (MJ/kg).
#   feed_data_summarised - one row per ingredient category (category1) with
#                          the mean nutrient values of its ingredients.
#
# To update the database, replace the CSV in data/ and adjust the file name
# below.
# =============================================================================


# IAFFD - full----
# Categories are derived from the first digit(s) of the FICD ingredient code.
log_info("data", "Reading feed ingredient database data/FICD 2025-10-27.csv")
feed_data <- read_csv("data/FICD 2025-10-27.csv", show_col_types = FALSE) %>%
  rename_with(str_to_lower) %>%
  mutate(
    category1 = case_when(
      str_starts(code, "1") ~ "fish",
      str_starts(code, "2") ~ "terrestrial",
      str_starts(code, "3") ~ "plant",
      str_starts(code, "4") ~ "microbial",
      str_starts(code, "5") ~ "oil",
      str_starts(code, "60") ~ "vitamin premix",
      str_starts(code, "61") ~ "amino acid",
      str_starts(code, "62") ~ "mineral premix",
      str_starts(code, "70") ~ "additive"
    ),
    category2 = case_when(
      category1 == "fish" & str_starts(description, "Fish meal") ~ "Fish meal"
    )
  ) %>%
  select(
    "category1", "category2", "description", "crude  protein (%)",
    "crude lipids (%)", "total cho (%)","ash (%)",  "gross energy -mj (mj/kg)"
    ) %>%
  rename(
    ingredient = "description",
    protein = "crude  protein (%)",
    lipid = "crude lipids (%)",
    carbohydrate = "total cho (%)",
    ash = "ash (%)",
    energy = "gross energy -mj (mj/kg)"
    )

log_info("data", "Feed data loaded: ", nrow(feed_data), " ingredients in ",
         n_distinct(feed_data$category1), " categories")
log_object("data", "First rows of feed_data:", head(feed_data))


# IAFFD - summarised----
# Mean composition per category; used by the "Simplified" tab.
feed_data_summarised <- feed_data %>%
  group_by(category1) %>%
  summarise(
    protein = mean(protein, na.rm = TRUE),
    lipid = mean(lipid, na.rm = TRUE),
    carbohydrate = mean(carbohydrate, na.rm = TRUE),
    ash = mean(ash, na.rm = TRUE),
    energy = mean(energy, na.rm = TRUE)
  ) %>%
  drop_na()

log_info("data", "Feed data summarised: ", nrow(feed_data_summarised), " categories")
log_object("data", "feed_data_summarised:", feed_data_summarised)



# test <- feed_data %>%
#   mutate(
#     part1 = str_split_fixed(ingredient, ",", 2)[, 1],
#     part2 = str_split_fixed(ingredient, ",", 2)[, 2] %>% str_trim()
#   )
#
# unique(test$part1)
