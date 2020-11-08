library(tidyverse)
library(rvest)
library(httr)
# GET cafe data

cafe =
  GET("https://data.cityofnewyork.us/resource/qcdj-rwhu.csv",
      query = list(
        "$limit" = 5000
      )) %>% 
  content("parsed")

cafe %>% write_csv(here::here("data","Sidewalk_Caf__Licenses_and_Applications.csv"))
