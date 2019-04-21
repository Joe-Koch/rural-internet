library(dplyr) 
library(RSQLite) 
library(rgdal) 
library(sqldf)
library(raster)

setwd(dirname(rstudioapi::getSourceEditorContext()$path))

# The US census population data file is massive, so we'll break it up by state.
# If a state doesn't have its own population data file already, we'll make one.
if(!file.exists(destfile)){
population_df = read.csv("data/us2017.csv")
state_population_df <- subset(population_df, population_df$stateabbr == "VT")
population_df$tractcode <- substr(state_population_df$block_fips, 1, 11)
write.csv(state_population_df, file = "state-population-data.csv")
rm(PopData)
}

# UPLOAD TRACT SHAPES

# Convert the government-provided tract shapefile into a geopackage.
state <- shapefile("data/VT/tl_2017_50_tract/tl_2017_50_tract.shp")
outname <- "data/VT/state.gpkg"
if (file.exists("data/VT/state.gpkg")) {
  file.remove("data/VT/state.gpkg")
}
writeOGR(state, dsn = outname, layer = "state", driver = "GPKG")
# Upload the geopackage that has the state's tract shapes with sqlite 
db <- src_sqlite("data/VT/state.gpkg")
print(db)
dbListTables(db$con)
# We'll rename the state table so we can replace with our own data it more easily.
dbGetQuery(db$con,'ALTER TABLE state RENAME TO Shapes' )
# We see the tract codes are stored in the GEOID column of the table Shapes
dbGetQuery(db$con,'pragma table_info("Shapes")' )
dbGetQuery(db$con,'select * from Shapes limit 3' )
dbGetQuery(db$con,'select geom, GEOID from Shapes order by GEOID limit 3' )

# INCLUDE POPULATION DATA
population_df = read.csv("data/VT/state-population-data.csv")
dbWriteTable(db$con, 'Population', population_df, overwrite=TRUE)
dbGetQuery(db$con,'pragma table_info("Population")' )
dbGetQuery(db$con,'select * from Population limit 3' )
# todo: turn TractCode into tractcode
# dbGetQuery(db$con,'drop table TractPop')
dbGetQuery(db$con,'create table TractPop as 
           SELECT stateabbr, TractCode, sum(pop2017)  as pop2017 
           FROM Population 
           GROUP BY TractCode' )
dbGetQuery(db$con,'pragma table_info("TractPop")' )
dbGetQuery(db$con,'select * from TractPop limit 3' )

# INCLUDE MAX ADVERTISED UPLOAD SPEED
# Upload the csv that has the maximum upload speeds.
speed_df = read.csv("data/VT/VT-data-Dec2017.csv")
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
 # curent plan: add pop2017 to TractSpeed. Then when creating main, do TractSpeed.MaxAdUp / TractSpeed.pop2017 as WtdMaxUp
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

# SAVE TO Main.gpkg
# Add this state's layer to the main geopackage
ogrListLayers("data/VT/state.gpkg")

state_layer <- readOGR("data/VT/state.gpkg")
writeOGR(state_layer, dsn="data/main.gpkg", layer="VT", driver="GPKG", overwrite_layer ="TRUE" )
ogrListLayers("data/main.gpkg")
ogrListLayers("data/main.gpkg")[1]

