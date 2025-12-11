# IAFFD - full----
feed_data <- read_csv("data/FICD 2025-10-27.csv") %>%
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

print("Feed data successfully loaded!")
print(head(feed_data))


# IAFFD - summarised----
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

print("Feed data successfully summarised!")
print(head(feed_data_summarised))


# test <- feed_data %>%
#   mutate(
#     part1 = str_split_fixed(ingredient, ",", 2)[, 1],
#     part2 = str_split_fixed(ingredient, ",", 2)[, 2] %>% str_trim()
#   )
#
# unique(test$part1)

