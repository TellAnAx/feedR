feed_data <- read_csv("data/FICD 2025-10-27.csv") %>%
  rename_with(str_to_lower) %>%
  mutate(
    category = case_when(
      str_starts(code, "1") ~ "fish",
      str_starts(code, "2") ~ "terrestrial",
      str_starts(code, "3") ~ "plant",
      str_starts(code, "4") ~ "microbial",
      str_starts(code, "5") ~ "oil",
      str_starts(code, "60") ~ "vitamin premix",
      str_starts(code, "61") ~ "amino acid",
      str_starts(code, "62") ~ "mineral premix",
      str_starts(code, "70") ~ "additive"
    )
  )




# Select relevant columns
feed_data <- feed_data[, c("Description", "Crude  Protein (%)", "Gross Energy -MJ (MJ/kg)")]
feed_data <- na.omit(feed_data)
names(feed_data) <- c("Ingredient", "Protein", "Energy")

test <- feed_data %>%
  mutate(
    part1 = str_split_fixed(Ingredient, ",", 2)[, 1],
    part2 = str_split_fixed(Ingredient, ",", 2)[, 2] %>% str_trim()
  )

unique(test$part1)
