#' Obtain daily climate data for an environment from NASA POWER data.
#'
#' @description
#' Function downloading daily weather data via the package \strong{nasapower}
#' based on longitude, latitude, planting and harvest date characterizing this
#' environment.
#'
#' @param environment \code{character} Name of the environment for which climate
#'   data should be extracted.
#'
#' @param info_environments \code{data.frame} object with at least the 4 first
#'   columns. \cr
#'   \enumerate{
#'     \item year: \code{numeric} Year label of the environment
#'     \item location: \code{character} Name of the location
#'     \item longitude: \code{numeric} longitude of the environment
#'     \item latitude: \code{numeric} latitude of the environment
#'     \item planting.date: (optional) \code{Date} YYYY-MM-DD
#'     \item harvest.date: (optional) \code{Date} YYYY-MM-DD
#'     \item elevation: (optional) \code{numeric}
#'     \item IDenv: \code{character} ID of the environment (location x year)\cr
#'   }
#'   \strong{The data.frame should contain as many rows as Year x Location
#'   combinations. Example: if only one location evaluated across four years, 4
#'   rows should be present.}
#'
#' @param et0 whether evapotranspiration should be calculated. False by default.
#'
#' @return a data.frame \code{data.frame} with the following columns extracted
#' from POWER data, according to requested parameters:
#' \enumerate{
#'   \item longitude \code{numeric}
#'   \item latitude \code{numeric}
#'   \item YEAR \code{numeric}
#'   \item MM \code{integer}
#'   \item DD \code{integer}
#'   \item DOY \code{integer}
#'   \item YYYYMMDD \code{Date}
#'   \item RH2M \code{numeric}
#'   \item T2M \code{numeric}
#'   \item T2M_MIN \code{numeric}
#'   \item T2M_MAX \code{numeric}
#'   \item PRECTOTCORR \code{numeric}
#'   \item ALLSKY_SFC_SW_DWN \code{numeric}
#'   \item T2MDEW \code{numeric}
#'   \item IDenv \code{character} ID environment for which weather data were
#'   downloaded.
#'   \item length.gs \code{difftime} length in days of the growing season
#'   for the environment.
#'   }
#'
#' @references
#' \insertRef{sparks2018nasapower}{learnMET}
#' \insertRef{zotarelli2010step}{learnMET}
#'
#' @author Cathy C. Westhues \email{cathy.jubin@@hotmail.com}
#' @export



get_daily_tables_per_env <-
  function(environment,
           info_environments,
           path_data,
           et0 = F,
           ...) {
    # Check that the data contain planting and harvest dates
    if (length(info_environments$planting.date) == 0) {
      stop("Planting date should be provided")
    }
    if (length(info_environments$harvest.date) == 0) {
      stop("Harvest date should be provided")
    }
    
    
    longitude <-
      info_environments[info_environments$IDenv == environment, "longitude"]
    latitude <-
      info_environments[info_environments$IDenv == environment, "latitude"]
    if ("elevation" %in% colnames(info_environments)) {
      elevation <-
        info_environments[info_environments$IDenv == environment, "elevation"]
    }
    planting.date <-
      info_environments[info_environments$IDenv == environment, "planting.date"]
    harvest.date <-
      info_environments[info_environments$IDenv == environment, "harvest.date"]
    length.growing.season <-
      difftime(harvest.date, planting.date, units = "days")
    
    
    list_climatic_variables <-
      c(
        "RH2M",
        "T2M",
        "T2M_MIN",
        "T2M_MAX",
        "PRECTOTCORR",
        "ALLSKY_SFC_SW_DWN",
        "T2MDEW",
        "WS2M"
      )
    
    
    if (!inherits(planting.date, "Date") ||
        !inherits(harvest.date, "Date")) {
      stop("planting.date and harvest.date should be given as Dates (y-m-d).")
    }
    
    daily_w_env <- nasapower::get_power(
      community = "AG",
      lonlat = c(longitude,
                 latitude),
      pars = list_climatic_variables,
      dates = c(planting.date, harvest.date),
      temporal_api = "DAILY"
    )
    
    daily_w_env[daily_w_env == -99] <- NA
    
    daily_w_env$ALLSKY_SFC_SW_DWN[is.na(daily_w_env$ALLSKY_SFC_SW_DWN)] <-
      0
    daily_w_env$PRECTOTCORR[is.na(daily_w_env$PRECTOTCORR)] <- 0
    
    
    
    ## Calculation of the vapor-pressure deficit: difference between the actual
    ## water vapor pressure and the saturation water pressure at a particular
    ## temperature
    
    mean_saturation_vapor_pressure <-
      get.es(tmin = daily_w_env$T2M_MIN, tmax = daily_w_env$T2M_MAX)
    actual_vapor_pressure <-
      get.ea.with.rhmean(
        tmin = daily_w_env$T2M_MIN,
        tmax = daily_w_env$T2M_MAX,
        rhmean = daily_w_env$RH2M
      )
    daily_w_env$vapr_deficit <-
      mean_saturation_vapor_pressure - actual_vapor_pressure
    
    if (et0) {
      if (!exists("elevation")) {
        elevation <-
          get_elevation(info_environments = info_environments,
                        path = path_data)
        daily_weather_data <-
          plyr::join(daily_weather_data, elevation[, c("IDenv", "elevation")],
                     by =
                       "IDenv")
      }
      
      
      daily_w_env$et0 <-
        penman_monteith_reference_et0(
          doy = daily_w_env$DOY,
          latitude = latitude,
          elevation = elevation,
          tmin = daily_w_env$T2M_MIN,
          tmax = daily_w_env$T2M_MAX,
          tmean = daily_w_env$T2M,
          solar_radiation = daily_w_env$ALLSKY_SFC_SW_DWN,
          wind_speed = daily_w_env$WS2M,
          rhmean = daily_w_env$RH2M,
          rhmax = NULL,
          rhmin = NULL,
          tdew = NULL,
          use_rh = TRUE
        )
    }
    
    daily_w_env$IDenv <- environment
    daily_w_env$length.gs <- length.growing.season
    colnames(daily_w_env)[which(colnames(daily_w_env) == "ALLSKY_SFC_SW_DWN")] <-
      "daily_solar_radiation"
    colnames(daily_w_env)[which(colnames(daily_w_env) == "LON")] <-
      "longitude"
    colnames(daily_w_env)[which(colnames(daily_w_env) == "LAT")] <-
      "latitude"
    
    
    daily_w_env <-
      plyr::join(daily_w_env, info_environments[, c("IDenv", "location", "year")])
    
    daily_w_env <- dplyr::arrange(daily_w_env, DOY)
    Sys.sleep(15)
    daily_w_env <- as.data.frame(daily_w_env)
    
    return(daily_w_env)
  }


#' Obtain soil data for a given environment
#'
#' @description
#' Function downloading soil data from SoilGrids database
#'
#' @param environment \code{character} Name of the environment for which climate
#'   data should be extracted.
#'
#' @param info_environments \code{data.frame} object with at least the 4 first
#'   columns. \cr
#'   \enumerate{
#'     \item year: \code{numeric} Year label of the environment
#'     \item location: \code{character} Name of the location
#'     \item longitude: \code{numeric} longitude of the environment
#'     \item latitude: \code{numeric} latitude of the environment
#'     \item planting.date: (optional) \code{Date} YYYY-MM-DD
#'     \item harvest.date: (optional) \code{Date} YYYY-MM-DD
#'     \item elevation: (optional) \code{numeric}
#'     \item IDenv: \code{character} ID of the environment (location x year)\cr
#'   }
#'   \strong{The data.frame should contain as many rows as Year x Location
#'   combinations. Example: if only one location evaluated across four years, 4
#'   rows should be present.}
#'
#'
#' @return a data.frame \code{data.frame} with the following columns extracted
#' from SoilGrids
#' \enumerate{
#'   \item IDenv \code{character}
#'   \item a list of soil features
#'
#'   }
#'
#' @references
#' \insertRef{poggio2021soilgrids}{learnMET}
#'
#' @author Cathy C. Westhues \email{cathy.jubin@@hotmail.com}
#' @export


get_soil_per_env <-
  function(environment,
           info_environments,
           ...) {
    out <- tryCatch({
      longitude <-
        info_environments[info_environments$IDenv == environment, "longitude"]
      latitude <-
        info_environments[info_environments$IDenv == environment, "latitude"]
      
      r <- httr::GET(
        url = paste0(
            "https://rest.isric.org/soilgrids/v2.0/properties/query?lon=",
            longitude,
            "&lat=",
            latitude,
    "&property=clay&property=nitrogen&property=ocd&property=ocs&property=phh2o&property=sand&property=silt&property=soc&property=bdod&property=cec&depth=0-5cm&depth=5-15cm&depth=15-30cm&depth=30-60cm&depth=60-100cm&value=mean"
      
          
        )
      )
      
      
      jsonRespParsed <- httr::content(r, as = "parsed")
      all_values <- list()
      n <- 1
      for (property in 1:length(jsonRespParsed$properties$layers)) {
        for (depth in 1:length(jsonRespParsed$properties$layers[[property]]$depths)) {
          all_values[[n]] <-
            jsonRespParsed$properties$layers[[property]]$depths[[depth]]$values$mean
          names(all_values[[n]]) <-
            paste0(
              jsonRespParsed$properties$layers[[property]]$name,
              "_",
              jsonRespParsed$properties$layers[[property]]$depths[[depth]]$label
            )
          
          
          n <- n + 1
          
          
        }
      }
      
     all_values_tb <- as.data.frame(t(unlist(all_values)))
     all_values_tb$IDenv <- environment
     Sys.sleep(20)
     return(all_values_tb)
    },
    error = function(cond) {
        message("Here's the original error message:")
        message(cond)
        # Choose a return value in case of error
        return(NULL)
    },
    warning = function(cond) {
        message(paste("URL caused a warning:", url))
        message("Here's the original warning message:")
        message(cond)
        # Choose a return value in case of warning
        return(NULL)
    }
    )
    return(out)
    }
      
    


