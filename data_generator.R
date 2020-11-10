library(tidyverse)
library(rvest)
library(httr)
if (!"sf" %in% installed.packages()) {
  install.packages('sf')
}
require(sf)

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# paging through API

paging =
  function(url, page = 1) {
    row_limit = 50000
    df = GET(url,
             query = list("$limit" = row_limit,
                          "$offset" = (page-1) * row_limit,
                          "$order"=":id")) %>%
      content("parsed")
    
    return(df)
  }
#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# GET street longtitude and latitude and borough as tibble

get_location = 
  function(location_name="Columbia University",
           .pd = NA){
    cat("\r",location_name)
    if (!is.na(.pd)){.pd$tick()$print()}
    
    location_name = str_c(
      "https://geosearch.planninglabs.nyc/v1/search?text=",
      location_name,", New York, NY")
    
    url =
      URLencode(location_name)
    
    df = read_sf(GET(url) %>% content("text"))
    
    if (nrow(df)==0){return(tibble(long = NA,lat = NA, borough = NA))}
    
    geometry = df%>% 
      pull(geometry) %>% 
      as.tibble() %>%
      mutate(geometry = as.character(geometry),
             geometry = str_replace_all(geometry,"c|[\\(\\)]","")) %>% 
      separate(geometry,into = c("long","lat"),sep = ",") %>% 
      mutate_all(as.numeric) %>% 
      summarise(long = mean(long),
                lat = mean(lat)) %>% 
      mutate(borough = 
               df %>% 
               slice(1) 
             %>% pull(borough))
    
    return(geometry)
  }


#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# Get all info from the large data via summon number as tibble
summon =
  function(summons_number) {
    data =
      GET(
        "https://data.cityofnewyork.us/resource/nc67-uf89.csv",
        query = list(
          "$where" = str_c("summons_number=", summons_number)
        )
      ) %>%
      content("parsed")
    return(data)
  }


#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# GET cafe data

cafe =
  paging("https://data.cityofnewyork.us/resource/qcdj-rwhu.csv") %>%
  left_join(read_csv(here::here("data/zipcode.csv"))) %>% 
  rename(long = longitude,
         lat = latitude,
         street_name = street)

cafe =
  cafe %>% 
  filter(business_name != "MULBERRY STREET BAR LLC") %>% 
  rbind(cafe %>% 
          filter(business_name == "MULBERRY STREET BAR LLC") %>%
          select(-long,-lat,-borough) %>% 
          unite("search_query",building,street_name,remove = F) %>% 
          mutate(geo = map(search_query,get_location)) %>% 
          unnest(geo) %>% 
          select(-search_query)
          )

cafe %>% 
  write_csv(here::here("data","Sidewalk_Caf__Licenses_and_Applications_clean.csv"))


#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
#GET ticket data
ticket = 
  GET("https://data.cityofnewyork.us/api/views/nc67-uf89/rows.csv?accessType=DOWNLOAD") %>% 
  content("parse")

write_csv(get_ticket(),here::here("data","Open_Parking_and_Camera_Violations.csv"))

cat("reference:", "https://mltconsecol.github.io/post/20180210_geocodingnyc/")

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# Cleaning parking 2021 data
## pull out address data

###pull out house number(without NA) +street number
park21house_geo_df = 
  read_csv("./data/Parking_Violations_Issued_-_Fiscal_Year_2021.csv") %>% 
  janitor::clean_names() %>% 
  subset(select= c(house_number, street_name)) %>% 
  drop_na(house_number) %>% 
  unite("address", house_number:street_name, sep = ",", remove = FALSE) %>%
  distinct(address, .keep_all = TRUE) %>% 
  rowid_to_column("id")

###pull out street number +intersect street(without NA) 
park21sec_geo_df = 
  read_csv("./data/Parking_Violations_Issued_-_Fiscal_Year_2021.csv") %>% 
  janitor::clean_names() %>% 
  subset(select= c(house_number, street_name, intersecting_street)) %>% 
  mutate(house_number = replace_na(house_number, "0")) %>% 
  filter(house_number == "0") %>% 
  drop_na(intersecting_street) %>% 
  unite("address", street_name:intersecting_street, sep = ",", remove = FALSE) %>% 
  distinct(address, .keep_all = TRUE) %>% 
  rowid_to_column("id") %>% 
  select(-house_number)



