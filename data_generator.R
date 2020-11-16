library(tidyverse)
library(rvest)
library(httr)
if (!"sf" %in% installed.packages()) {
  install.packages('sf')
}
require(sf)
library(tidyverse)
library(readxl)
if (!"reconPlots" %in% installed.packages()) {
install.packages("remotes")
remotes::install_github("andrewheiss/reconPlots")
}
require(reconPlots)

vec_to_df =
  function(vec){
    df = tibble(geo =vec) 
    return(df)
  }

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
##GET ticket data
#ticket = 
#  GET("https://data.cityofnewyork.us/api/views/nc67-uf89/rows.csv?accessType=DOWNLOAD") %>% 
#  content("parse")
#
write_csv(get_ticket(),here::here("data","Open_Parking_and_Camera_Violations.csv"))

cat("reference:", "https://mltconsecol.github.io/post/20180210_geocodingnyc/")

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# Cleaning parking 2021 data

## Drop unused data in 2021 data
data_2021 =  
  read_csv("./data/Parking_Violations_Issued_-_Fiscal_Year_2021.csv") %>% 
  janitor::clean_names() %>% 
  select(summons_number, issue_date, house_number, street_name, intersecting_street, violation_time, violation_code)

## pull out address data

###pull out house number(without NA) +street number
park21house_geo_df = 
  data_2021%>% 
  subset(select= c(house_number, street_name)) %>% 
  drop_na(house_number) %>% 
  unite("address", house_number:street_name, sep = ",", remove = FALSE) %>%
  distinct(address, .keep_all = TRUE) %>% 
  rowid_to_column("id")

###pull out street number +intersect street(without NA) 
park21sec_geo_df = 
  data_2021 %>% 
  subset(select= c(house_number, street_name, intersecting_street)) %>% 
  mutate(house_number = replace_na(house_number, "0")) %>% 
  filter(house_number == "0") %>% 
  drop_na(intersecting_street) %>% 
  unite("address", street_name:intersecting_street, sep = ",", remove = FALSE) %>% 
  distinct(address, .keep_all = TRUE) %>% 
  rowid_to_column("id") %>% 
  select(-house_number)

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# get geo for house (you can try to run all this)

while (T) {
  output = list()
  doit = function(output, i) {
    cat(i,"\n")
    pb = progress_estimated(length((1 + 500 * (i - 1)):500 * i))
    output[[i]] = park21house_geo_df %>%
      #arrange(desc(id)) %>%
      slice((1 + 500 * (i - 1)):500 * i) %>%
      mutate(geo = map(.x = address,  ~ get_location(.x, pb))) %>%
      unnest(geo)
    return(output[[i]])
  }
  for (i in 1:nrow(park21house_geo_df)%/%500+1) {
    park21house_geo_df =
      park21house_geo_df %>%
      filter(!id %in% pull(read_csv(here::here("data/cache.csv")), id))
    
    if (length(output) >= i) {
      if (!is.null(output[[i]])){next}
    }
    output[[i]] = tryCatch(doit(output, i),error = function(cond) return(NULL),T)
    output %>% 
      bind_rows() %>% 
      bind_rows(read_csv(here::here("data/cache.csv"))) %>%
      select(id:borough) %>% 
      write_csv(here::here("data/cache.csv"))
    output = list()
    }
  if (i == nrow(park21house_geo_df)%/%500+1) {
    park21house_geo_df = bind_rows(output)
    break
  }
}


st = 
  read_csv(here::here("data/Centerline.csv")) %>% 
  janitor::clean_names() %>% 
  select(street_name = full_stree,geom=the_geom) %>% 
  mutate(geom = str_extract_all(geom,"\\-.+,"),
         geom = str_split(geom,",\\s?"),
         geom = map(geom,vec_to_df)) %>%
  unnest(geom) %>% 
  separate(geo,into = c("long","lat"),sep = " ") %>% 
  drop_na() %>% 
  mutate(across(c(long,lat),as.numeric))

street_intersect =
  function(street_1,street_2,.pd = NULL){
    
    if (!is.na(.pd)){.pd$tick()$print()}
    
    street_1_df =
      st %>% 
      filter(street_name==
               agrep(street_1,st %>% pull(street_name),
                     value = T,
                     max =list(del = 0.4),
                     ignore.case = T) %>% first()) %>% 
      select(x = long, y = lat)
    
    street_2_df =
      st %>% 
      filter(street_name==
               agrep(street_2,st %>% pull(street_name),
                     value = T,
                     max =list(del = 0.4),
                     ignore.case = T) %>% first()) %>% 
      select(x = long, y = lat)
    answer = tryCatch(curve_intersect(street_1_df,street_2_df) %>% bind_rows(),
                      error = function(cond) return(tibble(x = NA,y=NA)),T)
    return(answer)
  }

pb = progress_estimated(nrow(park21sec_geo_df))
park21sec_geo_df =
  park21sec_geo_df %>%
  mutate(geo = map2(.x = street_name, 
                    .y =intersecting_street, 
                    ~street_intersect(.x,.y,pb))) %>%
  unnest(geo) %>%
  rename(long = x, lat = y)

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# Join with fine amount
fine_data =read_excel("data/ParkingViolationCodes_January2020.xlsx")%>% 
  janitor::clean_names()%>% 
  select(-violation_description)
fine_2021_data = 
  left_join(fine_data, data_2021, by = "violation_code")
  