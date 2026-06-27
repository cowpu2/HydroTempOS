
## ========= Load libraries and paths =================
##
## Utility file 
##
##
## CodeMonkey:  Mike Proctor
## ======================================================================  


Package_list <- c( 
                  "tidyverse"
                  , "tidylog"
                  , "here"
                  , "shiny"
                  , "plotly"
                  )

# for (package in Package_list) {
#   if (!require(package, character.only = TRUE)) {
#     renv::install(package)
#   }
#   
#   library(package, character.only = TRUE)
# }

for (package in Package_list) {
  if (!require(package, character.only = TRUE)) {
    install.packages(package, dependencies = TRUE)
  }
  
  library(package, character.only = TRUE)
}


rm(list = c("package", "Package_list"))

# After installing new packages, run renv::snapshot() to record them in renv.lock

## Local stuff  =================
source_path     <- "source_data"
dat_path        <- "dat_output"
plot_path       <- "plots"
csv_path        <- "csv_output"


# convert windows path
#gsub("\\\\", "/", readClipboard())
