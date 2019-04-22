# Driver for adding layers to the main geopackage and generating data visualizations.

library(ggplot2)

setwd(dirname(rstudioapi::getSourceEditorContext()$path))

# Add layers to the map geopackage.
source(file.path(getwd(), "map_maker_functions.R"))
VT_df <- add.state.layer("VT", file.path(getwd(), "/data/states/VT"), file.path(getwd(), "/data/main.gpkg"))
NH_df <- add.state.layer("NH", file.path(getwd(), "/data/states/NH"), file.path(getwd(), "/data/main.gpkg"))

# Data analysis for infographic
states_df <- rbind(VT_df, NH_df)

sum(states_df$MaxUploadSpd==1000)/nrow(states_df)
ggplot(states_df, aes(x=MaxUploadSpd)) + geom_histogram(breaks=seq(0, 1000, by=100)) +
  xlab("Maximum Advertised Upload Speed") + ylab("Count") + theme_bw()
sum(states_df$MaxUploadSpd==1000 & states_df$Pop2017<2500)/sum(states_df$MaxUploadSpd==1000)
ggplot(states_df[states_df$MaxUploadSpd==1000,], aes(x=Pop2017)) + geom_histogram(breaks=seq(0, 10500, by=1000)) + 
  xlab("Population") + ylab("Count") + theme_bw() 





