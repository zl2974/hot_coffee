library(tidyverse)
library(httr)
library(rvest)

table_zip =
  read_html("https://www.nycbynatives.com/nyc_info/new_york_city_zip_codes.php") %>% 
  html_node(css = "table") %>% 
  html_table() %>% 
  as.tibble() %>% 
  select(
    zipcode_1 = X1,
    boro_1 = X2,
    zipcode_2 = X4,
    boro_2 = X5
  )

table_zip =
  table_zip %>%
  unite("zip_1", c(zipcode_1, boro_1), sep = "-") %>%
  unite("zip_2", c(zipcode_2, boro_2), sep = "-") %>%
  pivot_longer(zip_1:zip_2,
               values_to = "zip") %>%
  separate(zip,
           into = c("zip", "borough"),
           sep = "-") %>%
  mutate(across(zip,as.numeric)) %>% 
  select(-name)

write_csv(table_zip,here::here("data","zipcode.csv"))