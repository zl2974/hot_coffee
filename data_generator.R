library(tidyverse)
library(rvest)
library(httr)
if (!"sf" %in% installed.packages()) {
  install.packages('sf')
}
require(sf)
library(readr)
library(tidyverse)
library(readxl)
if (!"reconPlots" %in% installed.packages()) {
  install.packages("remotes")
  remotes::install_github("andrewheiss/reconPlots")
}
require(reconPlots)

vec_to_df =
  function(vec) {
    df = tibble(geo = vec)
    return(df)
  }

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# paging through API

paging =
  function(url, page = 1) {
    row_limit = 50000
    df = GET(url,
             query = list(
               "$limit" = row_limit,
               "$offset" = (page - 1) * row_limit,
               "$order" = ":id"
             )) %>%
      content("parsed")
    
    return(df)
  }
#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# GET street longtitude and latitude and borough as tibble

get_location =
  function(location_name = "Columbia University",
           .pd = NA) {
    if (!is.na(.pd)) {
      .pd$tick()$print()
    }
    
    location_name = str_c(
      "https://geosearch.planninglabs.nyc/v1/search?text=",
      location_name,
      ", New York, NY&size=2"
    )
    
    url =
      URLencode(location_name)
    
    df = read_sf(GET(url) %>% content("text"))
    
    if (nrow(df) == 0) {
      return(tibble(
        long = NA,
        lat = NA,
        borough = NA
      ))
    }
    
    geometry = df %>%
      pull(geometry) %>%
      as.tibble() %>%
      mutate(geometry = as.character(geometry),
             geometry = str_replace_all(geometry, "c|[\\(\\)]", "")) %>%
      separate(geometry, into = c("long", "lat"), sep = ",") %>%
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
        query = list("$where" = str_c("summons_number=", summons_number))
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
  rbind(
    cafe %>%
      filter(business_name == "MULBERRY STREET BAR LLC") %>%
      select(-long,-lat,-borough) %>%
      unite("search_query", building, street_name, remove = F) %>%
      mutate(geo = map(search_query, get_location)) %>%
      unnest(geo) %>%
      select(-search_query)
  )

cafe %>%
  write_csv(here::here("data", "Sidewalk_Caf__Licenses_and_Applications_clean.csv"))


#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
##GET ticket data
#ticket =
#  GET("https://data.cityofnewyork.us/api/views/nc67-uf89/rows.csv?accessType=DOWNLOAD") %>%
#  content("parse")
#
#write_csv(get_ticket(),
#          here::here("data", "Open_Parking_and_Camera_Violations.csv"))

cat("reference:",
    "https://mltconsecol.github.io/post/20180210_geocodingnyc/")

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# Cleaning parking 2021 data

## Drop unused data in 2021 data
data_2021 =
  read_csv("./data/Parking_Violations_Issued_-_Fiscal_Year_2021.csv") %>%
  janitor::clean_names() %>%
  mutate(
    borough =
      case_when(
        violation_county %in% c("BK", "K") ~ "Brooklyn",
        violation_county %in% c("MN", "NY") ~ "Manhattan",
        violation_county %in% c("Q", "QN") ~ "Queens",
        violation_county %in% c("BX") ~ "Bronx"
      ),
    borough = replace_na(borough, "Staten Island")
  ) %>% 
  select(
    summons_number,
    issue_date,
    house_number,
    street_name,
    intersecting_street,
    violation_time,
    violation_code,
    borough
  )

## pull out address data

###pull out house number(without NA) +street number
park21house_geo_df =
  data_2021 %>%
  subset(select = c(house_number, street_name,borough)) %>%
  drop_na(house_number) %>%
  unite("address",
        house_number:borough,
        sep = ",",
        remove = FALSE) %>%
  distinct(address, .keep_all = TRUE) %>%
  rowid_to_column("id")

###pull out street number +intersect street(without NA)
park21sec_geo_df =
  data_2021 %>%
  subset(select = c(house_number, street_name, intersecting_street)) %>%
  mutate(house_number = replace_na(house_number, "0")) %>%
  filter(house_number == "0") %>%
  drop_na(intersecting_street) %>%
  unite("address",
        street_name:intersecting_street,
        sep = ",",
        remove = FALSE) %>%
  distinct(address, .keep_all = TRUE) %>%
  rowid_to_column("id") %>%
  select(-house_number)

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# get geo for house (you can try to run all this)
if (!file.exists("data/house_no_dic.csv")){
  
  if (nrow("data/cache.csv")==0){
    write_csv(tibble(id = NA),"data/cache.csv")
  }
  
  while (T) {
    output = list()
    doit = function(output, i) {
      cat(i, "\n")
      pb = progress_estimated(length((1 + 500 * (i - 1)):500 * i))
      output[[i]] = park21house_geo_df %>%
        #arrange(desc(id)) %>%
        slice((1 + 500 * (i - 1)):500 * i) %>%
        mutate(geo = map(.x = address,  ~ get_location(.x, pb))) %>%
        unnest(geo)
      return(output[[i]])
    }
    for (i in 1:nrow(park21house_geo_df) %/% 500 + 1) {
      park21house_geo_df =
        park21house_geo_df %>%
        filter(!id %in% pull(read_csv(here::here(
          "data/cache.csv"
        )), id))
      
      if (length(output) >= i) {
        if (!is.null(output[[i]])) {
          next
        }
      }
      output[[i]] = tryCatch(
        doit(output, i),
        error = function(cond)
          return(NULL),
        T
      )
      output %>%
        bind_rows() %>%
        bind_rows(read_csv(here::here("data/cache.csv"))) %>%
        select(id:borough) %>%
        write_csv(here::here("data/cache.csv"))
      output = list()
    }
    if (i == nrow(park21house_geo_df) %/% 500 + 1) {
      park21house_geo_df = bind_rows(output)
      break
    }
  }
  
  
  st =
    read_csv(here::here("data/Centerline.csv")) %>%
    janitor::clean_names() %>%
    select(street_name = full_stree, geom = the_geom) %>%
    mutate(
      geom = str_extract_all(geom, "\\-.+,"),
      geom = str_split(geom, ",\\s?"),
      geom = map(geom, vec_to_df)
    ) %>%
    unnest(geom) %>%
    separate(geo, into = c("long", "lat"), sep = " ") %>%
    drop_na() %>%
    mutate(across(c(long, lat), as.numeric))
  
  street_intersect =
    function(street_1, street_2, .pd = NULL) {
      if (!is.na(.pd)) {
        .pd$tick()$print()
      }
      
      street_1_df =
        st %>%
        filter(
          street_name ==
            agrep(
              street_1,
              st %>% pull(street_name),
              value = T,
              max = list(del = 0.4),
              ignore.case = T
            ) %>% first()
        ) %>%
        select(x = long, y = lat)
      
      street_2_df =
        st %>%
        filter(
          street_name ==
            agrep(
              street_2,
              st %>% pull(street_name),
              value = T,
              max = list(del = 0.4),
              ignore.case = T
            ) %>% first()
        ) %>%
        select(x = long, y = lat)
      answer = tryCatch(
        curve_intersect(street_1_df, street_2_df) %>% bind_rows(),
        error = function(cond)
          return(tibble(x = NA, y = NA)),
        T
      )
      return(answer)
    }
  
  pb = progress_estimated(nrow(park21sec_geo_df))
  park21sec_geo_df =
    park21sec_geo_df %>%
    mutate(geo = map2(.x = street_name,
                      .y = intersecting_street,
                      ~ street_intersect(.x, .y, pb))) %>%
    unnest(geo) %>%
    rename(long = x, lat = y)
}

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# clean the parking_violation issued-fiscal_year_2021 data, and add geographic information to it


house_no_dic =
  read_csv("./data/house_no_dic.csv") %>%
  subset(select = -c(id, geo)) %>% 
  mutate(borough =
           if_else(between(lat,40.75,40.78)& borough == "Bronx",
                   "Manhattan",borough),
         borough =
           if_else(lat < 40.75 & borough == "Bronx",
                   "Brooklyn",borough))


data_2021_cleanv1 =
  read_csv("./data/Parking_Violations_Issued_-_Fiscal_Year_2021.csv") %>%
  janitor::clean_names() %>%
  rowid_to_column("id") %>%
  subset(
    select = c(
      id,
      summons_number,
      registration_state,
      issue_date,
      violation_code,
      vehicle_make,
      violation_time,
      violation_county,
      house_number,
      street_name,
      intersecting_street,
      vehicle_color,
      vehicle_year
    )
  ) %>%
  left_join(house_no_dic, by = c("house_number", "street_name")) %>% 
  separate(violation_time,
           into = c('hour', 'min', 'am_pm'),
           sep = c(2, 4)) %>%
  mutate(
    am_pm = recode(am_pm, `P` = 12, `A` = 0),
    hour = as.numeric(hour),
    hour = ifelse((hour == 12 &
                     am_pm == 12), hour, (hour + am_pm)),
    issue_date = as.Date(issue_date, tryFormats = "%m/%d/%Y")
  ) %>%
  subset(select = c(-am_pm)) %>%
  unite("time", hour:min, remove = F, sep = ":") %>%
  unite("issue_date",
        c(issue_date, time),
        remove = T,
        sep = "T") %>%
  mutate(issue_date = lubridate::ymd_hm(issue_date)) %>% 
  mutate(
    borough =
      case_when(
        violation_county %in% c("BK", "K") ~ "Brooklyn",
        violation_county %in% c("MN", "NY") ~ "Manhattan",
        violation_county %in% c("Q", "QN") ~ "Queens",
        violation_county %in% c("BX") ~ "Bronx"
      ),
    borough = replace_na(borough, "Staten Island")
  )

st_sample = #get ready for resample
  function(st_name, n = 1) {
    cat("\r", st_name)
    a = data_2021_cleanv1 %>%
      filter(!is.na(long), street_name == st_name)
    if (nrow(a) > 0) {
      a %>% 
      select(long, lat, borough) %>%
        sample_n(size = n, replace = TRUE) %>%
        return()
    } else{
      data_2021_cleanv1 %>%
        filter(!is.na(long),!is.na(address)) %>%
        select(long, lat, borough) %>%
        sample_n(size = n, replace = TRUE) %>%
        return()
    }
  }

set.seed(1) # resample for intersection
dic = data_2021_cleanv1 %>%
  filter(!is.na(street_name), is.na(long)) %>%
  select(summons_number, street_name) %>%
  nest(summons_number) %>%
  mutate(n = map(data, nrow),
         geo =
           map2(.x = street_name, .y = n, ~ st_sample(st_name = .x, n = .y))) %>% 
  unnest(c(data,geo)) %>% 
  select(-n) %>% 
  distinct(summons_number,.keep_all = T)

data_2021_cleanv1 =
  data_2021_cleanv1 %>% #putting sample data into the main data
  left_join(dic, by = "summons_number", suffix = c("", "_d")) %>%
  mutate(
    long = if_else(is.na(long), long_d, long),
    lat = if_else(is.na(lat), lat_d, lat),
    borough = if_else(is.na(borough), borough_d, borough),
    hour = if_else(hour<=24,as.integer(hour),NA)
  ) %>%
  select(id:borough)

##>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
## Join with fine amount

st_96 = lm(lat~long,read_csv("data/96th.csv"))

fine_data = read_excel("data/ParkingViolationCodes_January2020.xlsx") %>%
  janitor::clean_names() %>%
  select(-violation_description) %>% 
  pivot_longer(
    manhattan_96th_st_below_fine_amount:all_other_areas_fine_amount,
    names_to = "below_96",
    values_to = "fine_amount"
  ) %>% 
  mutate(below_96_m = 
           case_when(below_96 == "manhattan_96th_st_below_fine_amount" ~T,
                     below_96 != "manhattan_96th_st_below_fine_amount" ~F)) %>% 
  select(-below_96)

data_2021_cleanv1 = data_2021_cleanv1 %>%
  mutate(below_96 =
           lat < predict(st_96,
                         tibble(long = data_2021_cleanv1$long)),
         below_96_m = ifelse(borough == "Manhattan" & below_96 == TRUE, T, F)
         ) %>% 
  left_join(fine_data, by = c("violation_code","below_96_m")) %>% 
  select(-below_96, -below_96_m) 
 

write_csv(data_2021_cleanv1, "./data/parking_vio2021_cleanv1.csv")


