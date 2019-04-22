# rural-internet

Code for visualizing maximum advertised upload speeds by census tract for New Hampshire and Vermont, weighting upload speeds by population. The visualization can be seen [here](http://dev.carto.ruralinnovation.us/user/zoekoch/builder/7dd9e4ef-fe63-49f2-ac68-22f870f52563/embed).

The script map_maker.R adds VT and NH layers to the main geopackage and generates the histograms in the [summary slide](https://github.com/ZoeKoch/rural-internet/blob/master/data/images/summary-slide.pdf). It uses the function add.state.layer from  map_maker_functions.R. This function takes a shape file of the census tract shapes, converts it into a geopackage state.gpkg, uploads it into R using SQLite, appends the population data and internet speed data, and adds the state.gpkg as a layer named after the state's abbreviation in main.gpkg. The weighted max upload speed variable is just the tract's maximum upload speed divided by the tract population. 

#### Data sources:
* Broadband Data Source: the latest [FCC Form 477](https://www.fcc.gov/general/broadband-deployment-data-fcc-form-477) wireline deployment data release
* Population: [FCC estimates](https://www.fcc.gov/reports-research/data/staff-block-estimates) of housing unit, household and population counts for each block for 2010 (US Census) and 2017 (Commission staff estimate)
* Tract shapes: tract-level shapefiles from the [United States Census Bureau](https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.2017.html), as of January 1, 2017.

## Steps to add more states to the map:
Say you're adding Utah (UT) to the map.
1. Create a new folder, data/states/UT containing the UT-data-Dec2017.csv from [the FCC](https://www.fcc.gov/general/broadband-deployment-data-fcc-form-477) and an unzipped shapefile from [the United States Census Bureau](https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.2017.html). Do not rename or delete anything from the shapefile, just unzip it.
2. Make sure you have all the packages used in map_maker_functions.R imported.
3. In map_maker.R, anywhere after `source(file.path(getwd(), "map_maker_functions.R"))`
, run 
```R
add.state.layer("UT", file.path(getwd(), "/data/states/UT"), file.path(getwd(), "/data/main.gpkg"))
```
That's all. You should now have a UT layer in the main.gpkg, and in a new state.gpkg in the data/state/UT folder.
