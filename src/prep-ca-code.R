################################################################################
#' @description Create CA CODE sex-combined age group for 15-19y, aggregate deaths for SDG regions
#' @return Data frame with deaths and population counts for countries, regions, age, sex, year  
################################################################################
#' Clear environment
rm(list=ls())
#' Libraries
library(data.table)
#' Inputs
## CA-CODE 2000-2021 results
list_csv_files <- list.files(path = "./data/ca-code/",  pattern = "*.csv")
list_csv_files <- list_csv_files[grepl("national", list_csv_files, ignore.case = TRUE)]
l_cacode <- lapply(list_csv_files, function(x) read.csv(paste0("./data/ca-code/", x), 
                                                        stringsAsFactors = FALSE))
names(l_cacode) <- sub('\\.csv.*', '', list_csv_files)
## GHE 2021 deaths aggregated by CA CODE COD categories
ghe <- readRDS("./gen/ghe-agg-reg.rds")
## Region key
key <- read.csv("./gen/key_region.csv")
################################################################################

# Convert to data frame
dat <- do.call(dplyr::bind_rows, l_cacode)

# Remove countries not reported in GHE
# Some small countries not reported in GHE
unique(dat$ISO3)[!(unique(dat$ISO3) %in% unique(ghe$Name))]
# Only include countries reported in GHE
dat <- subset(dat, ISO3 %in% unique(ghe$Name))

# Create new age group variable
dat$AgeGroup <- NA
dat$AgeGroup[dat$AgeLow == 5 & dat$AgeUp == 9] <- "05to09y"
dat$AgeGroup[dat$AgeLow == 10 & dat$AgeUp == 14] <-  "10to14y"
dat$AgeGroup[dat$AgeLow == 15 & dat$AgeUp == 19] <-  "15to19y"

# Recode "Sex"
dat$Sex[dat$Sex == "Both"] <- "Total"

# Recode "Maternal" as NA for males instead of 0
# dat$Maternal[dat$Sex %in% c("Male", "Total")] <- NA

# Remove unnecessary columns
dat <- dat[,-which(names(dat) %in% c("AgeLow","AgeUp","Model","FragileState","WHOname","UNICEFReportRegion1","UNICEFReportRegion2","Region"))]

# Merge on income region
dat <- merge(dat, key[,c("iso3","wbinc13")], all.x = TRUE, by.x = "ISO3", by.y = "iso3")

# Calculate deaths for 15-19y sex-combined --------------------------------

dat15to19y <- subset(dat, Variable == "Deaths" & AgeGroup == "15to19y")
dat15to19y$Sex <- NULL
# # Add Maternal to OtherCMPN and recode Maternal as NA
# dat15to19y$OtherCMPN <- ifelse(!is.na(dat15to19y$Maternal), dat15to19y$Maternal + dat15to19y$OtherCMPN, dat15to19y$OtherCMPN)
# dat15to19y$Maternal <- NA
# Grouping variables for aggregation
v_grouping <- c("ISO3", "Year", "AgeGroup", "SDGregion", "wbinc13", "Variable","Quantile")
v_cod <- names(dat15to19y)[!(names(dat15to19y) %in% v_grouping)]
# Aggregate deaths over sex
dat15to19y <- setDT(dat15to19y)[, lapply(.SD,sum), by=v_grouping]
dat15to19y <- as.data.frame(dat15to19y)
dat15to19y$Sex <- "Total"
# Transform into fractions
dat15to19yfrac <- dat15to19y
dat15to19yfrac[, v_cod] <- round(dat15to19yfrac[, v_cod] / rowSums(dat15to19yfrac[, v_cod], na.rm = TRUE), 5)
dat15to19yfrac$Variable <- "Fraction"
# Add back with all data
dat <- rbind(dat, dat15to19y, dat15to19yfrac)

# Aggregate by SDG region -------------------------------------------------

# Delete unnecessary columns prior to aggregation
v_del <- c("ISO3", "wbinc13")
dat_reg <- as.data.frame(dat)[,!(names(dat) %in% v_del)]
dat_reg <- subset(dat_reg, Variable == "Deaths")
# Grouping variables for aggregation
v_grouping <- c("SDGregion","Sex", "Year", "AgeGroup", "Variable", "Quantile")
v_cod <- names(dat_reg)[!(names(dat_reg) %in% v_grouping)]
# Aggregate deaths over regions
dat_agg_sdg <- setDT(dat_reg)[,lapply(.SD, sum), by=v_grouping]
# Create world region
dat_world <- dat_agg_sdg
dat_world$SDGregion <- "World"
dat_world <- setDT(dat_world)[,lapply(.SD, sum), by=v_grouping]
# Combine with regions
dat_agg_sdg <- rbind(dat_agg_sdg, dat_world)
# Transform into fractions
dat_agg_sdg <- as.data.frame(dat_agg_sdg)
dat_agg_sdg[, v_cod] <- round(dat_agg_sdg[, v_cod] / rowSums(dat_agg_sdg[, v_cod], na.rm = TRUE), 5)
dat_agg_sdg$Variable <- "Fraction"

# Aggregate by income region ----------------------------------------------

# Delete unnecessary columns prior to aggregation
v_del <- c("ISO3", "SDGregion")
dat_reg <- as.data.frame(dat)[,!(names(dat) %in% v_del)]
dat_reg <- subset(dat_reg, Variable == "Deaths")
# Grouping variables for aggregation
v_grouping <- c("wbinc13","Sex", "Year", "AgeGroup", "Variable", "Quantile")
v_cod <- names(dat_reg)[!(names(dat_reg) %in% v_grouping)]
# Aggregate deaths over regions
dat_agg_inc <- setDT(dat_reg)[,lapply(.SD, sum), by=v_grouping]
# Transform into fractions
dat_agg_inc <- as.data.frame(dat_agg_inc)
dat_agg_inc[, v_cod] <- round(dat_agg_inc[, v_cod] / rowSums(dat_agg_inc[, v_cod], na.rm = TRUE), 5)
dat_agg_inc$Variable <- "Fraction"


# Combine -----------------------------------------------------------------

# Harmonize column names

# National level data
v_del <- c("ISO3", "SDGregion", "wbinc13")
dat$Name <- dat$ISO3
dat$AdminLevel <- "National"
dat <- as.data.frame(dat)[,!(names(dat) %in% v_del)]

# SDG regions
dat_agg_sdg$Name <- dat_agg_sdg$SDGregion
dat_agg_sdg$AdminLevel <- "RegionalSDG"
dat_agg_sdg$AdminLevel[dat_agg_sdg$Name == "World"] <- "Global"
dat_agg_sdg <- as.data.frame(dat_agg_sdg)[,!(names(dat_agg_sdg) %in% v_del)]

# Income regions
dat_agg_inc$Name <- dat_agg_inc$wbinc13
dat_agg_inc$AdminLevel <- "RegionalInc"
dat_agg_inc <- as.data.frame(dat_agg_inc)[,!(names(dat_agg_inc) %in% v_del)]

# Recombine national and regional
dat <- rbind(dat, dat_agg_sdg, dat_agg_inc)

# Only keep fractions
dat <- subset(dat, Variable == "Fraction")
dat$Variable <- NULL

# Reshape to long
v_id_cols <- c("AgeGroup", "AdminLevel","Name", "Year", "Sex", "Quantile")
dat_long <- melt(setDT(dat), id.vars = v_id_cols, variable.factor = FALSE)

# Make uncertainty columns wide
dat_lb <- subset(dat_long, Quantile == "Lower")
dat_lb$Quantile <- NULL
dat_pt <- subset(dat_long, Quantile == "Point")
dat_pt$Quantile <- NULL
dat_ub <- subset(dat_long, Quantile == "Upper")
dat_ub$Quantile <- NULL
dat_wide <- merge(dat_pt, dat_lb, by = c("AgeGroup", "AdminLevel","Name","Year","Sex","variable"), suffixes = c("","_lb"))
dat_wide <- merge(dat_wide , dat_ub, by = c("AgeGroup", "AdminLevel","Name","Year","Sex","variable"), suffixes = c("","_ub"))
dat_wide <- subset(dat_wide, !is.na(value))

# Rename columns
names(dat_wide)[which(names(dat_wide) == "variable")] <- "cacodecause"
names(dat_wide)[which(names(dat_wide) == "value")] <- "frac"
names(dat_wide)[which(names(dat_wide) == "value_lb")] <- "frac_lb"
names(dat_wide)[which(names(dat_wide) == "value_ub")] <- "frac_ub"
names(dat_wide)[which(names(dat_wide) == "Year")] <- "year"
names(dat_wide)[which(names(dat_wide) == "Sex")] <- "sex"

# Tidy
dat_wide <- dat_wide[order(dat_wide$AdminLevel, dat_wide$Name, dat_wide$AgeGroup, dat_wide$sex, dat_wide$year),]

# Save output(s) ----------------------------------------------------------

saveRDS(dat_wide, "./gen/ca-code-frac.rds")


