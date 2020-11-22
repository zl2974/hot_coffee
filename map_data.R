library(flexdashboard)
library(tidyverse)
library(plotly)
library(leaflet)
library(shiny)
library(httr)
library(rvest)
library(sf)

cafe = read_csv(here::here("data/Sidewalk_Caf__Licenses_and_Applications_clean.csv")) %>% 
  left_join(read_csv(here::here("data/zipcode.csv"))) %>% 
  unite("adress",
        building:state,
        sep = ",") %>% 
  select(business_name,adress,starts_with("swc"),long,lat,borough)

parking = read_csv(here::here("data/parking_vio2021_cleanv1.csv")) %>% 
  select(id,long,lat,issue_date)

get_nearby_area =
  function(p_long = 0, p_lat = 0,area=100) {
    return(
      tibble(
        long_lwr = p_long - area / (6378137 * cos(pi * p_lat / 180)) * 180 / pi,
        long_upr = p_long + area / (6378137 * cos(pi * p_lat / 180)) * 180 /
          pi,
        lat_lwr = p_lat - area / 6378137 * 180 / pi,
        lat_upr = p_lat + area / 6378137 * 180 / pi
      )
    )
  }

get_data =
  function(area) {
    data =
      parking %>%
      bind_cols(area) %>%
      filter(long < long_upr,
             long > long_lwr,
             lat < lat_upr,
             lat > lat_lwr) %>% 
      select(id,issue_date)
    
    return(data)
  }

cafe =
  cafe %>%
  mutate(
    nearby = map2(.x = long, .y = lat, ~ get_nearby_area(.x, .y)),
    nearby = map(.x = nearby,  ~ get_data(.x)),
    ticket = map_dbl(nearby, nrow)) %>% 
  drop_na(borough) %>% 
  unnest(nearby) %>% 
  mutate(hour = lubridate::hour(issue_date),
         weekday = weekdays(issue_date),
         weekday = 
           forcats::fct_relevel(weekday,
                                c("Monday","Tuesday","Wednesday","Thursday",
                                  "Friday","Saturday","Sunday"))) %>% 
  group_by(hour,weekday,borough) %>% 
  mutate(risk = n()) %>% 
  ungroup() %>% 
  distinct(business_name,hour,weekday,.keep_all = T) %>% 
  select(-id,-issue_date,-weekday,-hour,-risk)

write_csv(cafe,"data/map_data.csv")

rm(parking)