# This file contains functions used in map_maker.

add.state.layer <- function(state_abbreviation, state_data_path, main_geopackage) {
  # Adds a layer named after the state's abbreviation to the main geopackage you specify in main_geopackage.
  # The layer will contain the maximum advertised upload speed available and the total population of each tract in the state.
  # If a state-population-2017.csv doesn't exist in the state_data_path folder, a new one will be created containing the 
  # state's population data from the FCC's estimates found in
  # https://www.fcc.gov/reports-research/data/staff-block-estimates/us2017.csv 
  # Warning: will overwrite the state's layer in the main geopackage and the state's geopackage.
  # 
  # Args:
  #   state_abbreviation: The state abbreviation , e.g. "VT"
  #   state_data_path: The path to the folder that holds the state's data files. Must contain a tl_2017_50_tract shapefile 
  #   folder with the state's tract-level geometries, and a csv file containing the FCC internet speed data, e.g.
  #   "VT-data-Dec2017.csv"
  #   main_geopackage: The path to the geopackage that you want to append the state's layer onto.
  
  library(dplyr) 
  library(RSQLite) 
  library(rgdal) 
  library(sqldf)
  library(raster)
  
  # EXTRACT THE POPULATION DATA FROM us2017.csv
  # If a state doesn't have its own population data file already, we'll make one now.
  if(!file.exists(file.path(state_data_path,"state-population-2017.csv"))){
    temp <- tempfile()
    # This data file provides housing unit, household and population counts for each block for 2010 (US Census) 
    # and 2017 (Commission staff estimate). https://www.fcc.gov/reports-research/data/staff-block-estimates
    download.file("https://transition.fcc.gov/bureaus/wcb/cpd/us2017.csv.zip",temp)
    us_population_df <- read.csv(unz(temp, "us2017.csv"))
    # The US census population data file is massive, so we'll break it up by state and keep that .csv.
    state_population_df <- subset(us_population_df, us_population_df$stateabbr == state_abbreviation)
    rm(us_population_df)
    unlink(temp)
    write.csv(state_population_df, file = file.path(state_data_path,"state-population-2017.csv"))
  }
  
  # UPLOAD TRACT SHAPES
  
  # Convert the government-provided tract shapefile into a geopackage state.gpkg . 
  state <- shapefile(Sys.glob(file.path(state_data_path, "tl_2017_*_tract/tl_2017_*_tract.shp")))
  state_gpkg <- file.path(state_data_path, "state.gpkg")
  if (file.exists(state_gpkg)) {
    file.remove(state_gpkg)
  }
  writeOGR(state, dsn = state_gpkg, layer = "state", driver = "GPKG")
  # Upload the geopackage that has the state's tract shapes with sqlite 
  db <- src_sqlite(state_gpkg)
  print(db)
  dbListTables(db$con)
  # We'll rename the state table so we can replace with our own data it more easily.
  dbGetQuery(db$con,'ALTER TABLE state RENAME TO Shapes' )
  # We see the tract codes are stored in the GEOID column of the table Shapes
  dbGetQuery(db$con,'pragma table_info("Shapes")' )
  dbGetQuery(db$con,'select * from Shapes limit 3' )
  dbGetQuery(db$con,'select geom, GEOID from Shapes order by GEOID limit 3' )
  
  # INCLUDE POPULATION DATA
  state_population_df = read.csv(file.path(state_data_path,"state-population-2017.csv"))
  # Create tractcode variable from block_fips
  state_population_df$tractcode <- substr(state_population_df$block_fips, 1, 11) 
  # Add population dataframe to the state geopackage as a table
  dbWriteTable(db$con, 'Population', state_population_df, overwrite=TRUE)
  dbGetQuery(db$con,'pragma table_info("Population")' )
  dbGetQuery(db$con,'select * from Population limit 3' )
  # Create a tract-level table
  dbGetQuery(db$con,'create table TractPop as 
             SELECT stateabbr, tractCode, sum(pop2017)  as pop2017 
             FROM Population 
             GROUP BY tractCode' )
  dbGetQuery(db$con,'pragma table_info("TractPop")' )
  dbGetQuery(db$con,'select * from TractPop limit 3' )
  
  # INCLUDE MAX ADVERTISED UPLOAD SPEED
  # Upload the csv that has the maximum upload speeds, data from 
  # https://www.fcc.gov/general/broadband-deployment-data-fcc-form-477
  # Download link:
  # https://transition.fcc.gov/form477/BroadbandData/Fixed/Dec17/Version%201/VT-Fixed-Dec2017.zip
  speed_df = read.csv(file.path(state_data_path,paste(state_abbreviation,"-data-Dec2017.csv",sep="")))
  # Create the tract code variable. The first 11 digits of a census block FIPS code are equal to the location's census tract FIPS code. 
  speed_df$TractCode <- substr(speed_df$BlockCode, 1, 11)
  # Put the dataframe into a table in our database.
  dbWriteTable(db$con, 'Speed', speed_df, overwrite=TRUE)
  dbGetQuery(db$con,'select * from Speed limit 3' )
  dbGetQuery(db$con, 'drop table if exists TractSpeed')
  dbGetQuery(db$con,'create table TractSpeed as 
             SELECT StateAbbr, TractCode, MAX(MaxAdUp) as MaxAdUp
             FROM Speed 
             GROUP BY TractCode' )
  dbGetQuery(db$con,'select * from TractSpeed limit 3' )
  
  # CREATE THE MAIN TABLE
  # Create a state table that's just the variables of interest. These will appear as widget options in CARTO.
  
  # If state already exists, we'll need to get rid of it before creating a new one.
  dbGetQuery(db$con, 'drop table if exists state')
  # Important note: we must specify the data type for the INT's, otherwise the datatype may be unspecified and CARTO won't load it.
  dbGetQuery(db$con,'create table state(geom BLOB, TractCode TEXT, StateAbbr TEXT, Pop2017 INT, MaxUploadSpd INT, WTDMaxUploadSpd INT)' )
  dbGetQuery(db$con,'INSERT INTO state(geom, TractCode, StateAbbr, Pop2017, MaxUploadSpd, WTDMaxUploadSpd)
             SELECT Shapes.geom, Shapes.GEOID as TractCode, TractSpeed.StateAbbr, TractPop.pop2017 as Pop2017,
             TractSpeed.MaxAdUp as MaxUploadSpd, TractSpeed.MaxAdUp / TractPop.pop2017 as WtdMaxUploadSpd
             FROM Shapes
             LEFT JOIN TractSpeed ON Shapes.GEOID = TractSpeed.TractCode
             LEFT JOIN TractPop ON Shapes.GEOID = TractPop.TractCode' )
  dbGetQuery(db$con,'pragma table_info("state")' )
  dbGetQuery(db$con, 'select * from state limit 3')
  # There were no tract codes in the shapes file that didn't have some population data or maximum upload speed.
  dbGetQuery(db$con, 'SELECT count(*) FROM state WHERE Pop2017 IS NULL')
  dbGetQuery(db$con, 'SELECT count(*) FROM state WHERE MaxUploadSpd IS NULL')
  
  # Get rid of the tables we don't need/want in the final geopackage.
  dbGetQuery(db$con, 'drop table if exists Shapes')
  dbGetQuery(db$con, 'drop table if exists Population')
  dbGetQuery(db$con, 'drop table if exists Speed')
  dbGetQuery(db$con, 'drop table if exists TractPop')
  dbGetQuery(db$con, 'drop table if exists TractSpeed')
  
  # We're finished with the database.
  dbDisconnect(db$con)
  
  # SAVE THIS STATE'S LAYER TO THE MAIN GEOPACKAGE
  ogrListLayers(state_gpkg)
  state_layer <- readOGR(state_gpkg)
  writeOGR(state_layer, dsn=main_geopackage, layer=state_abbreviation, driver="GPKG", overwrite_layer ="TRUE" )
  ogrListLayers(main_geopackage)
  ogrListLayers(main_geopackage)[1]
  
}