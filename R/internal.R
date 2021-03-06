#' function to convert lat long to xyz tile with decimals
#' rounding to tile occurs in \code{get_tilexy}
#' @keywords internal
latlong_to_tilexy <- function(lon_deg, lat_deg, zoom){
  #Code from https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames#Coordinates_to_tile_numbers_2
  lat_rad <- lat_deg * pi /180
  n <- 2.0 ^ zoom
  xtile <- (lon_deg + 180.0) / 360.0 * n
  ytile <- (1.0 - log(tan(lat_rad) + (1 / cos(lat_rad))) / pi) / 2.0 * n
  return(c(xtile, ytile))
}

#' function to get a data.frame of all xyz tiles to download
#' @keywords internal
get_tilexy <- function(bbx,z){
  min_tile <- latlong_to_tilexy(bbx[1,1],bbx[2,1],z)
  max_tile <- latlong_to_tilexy(bbx[1,2],bbx[2,2],z)
  x_all <- seq(from = floor(min_tile[1]), to = ceiling(max_tile[1]))
  y_all <- seq(from = ceiling(min_tile[2]), to = floor(max_tile[2]))
  if(z == 1){
    x_all <- x_all[x_all<2]
    y_all <- y_all[y_all<2]
  } else if(z == 0){
    x_all <- x_all[x_all<1]
    y_all <- y_all[y_all<1]
  }
  return(expand.grid(x_all,y_all))
}

#' function to check input type and projection.  All input types convert to a
#' SpatialPointsDataFrame for point elevation and bbx for raster.
#' @importFrom sp wkt
#' @importFrom sf st_crs
#' @keywords internal
loc_check <- function(locations, prj = NULL){
  
  prj <- st_crs(prj)
  
  #Convert sf locations to SP
  if(("sf" %in% class(locations)) | ("sfc" %in% class(locations))){
    locations <- sf::as_Spatial(locations)
  }
  
  if(is.null(nrow(locations))){
    nfeature <- length(locations) 
  } else {
    nfeature <- nrow(locations)
  }
  
  if(class(locations)=="data.frame"){ 
    if(is.na(prj)){
      stop("Please supply a valid crs.")
    }
    if(ncol(locations) > 2){
      df <- data.frame(locations[,3:ncol(locations)],
                       vector("numeric",nfeature))
      names(df) <- c(names(locations)[3:ncol(locations)],
                     "elevation")
    } else {
      df <- data.frame(vector("numeric",nfeature))
      names(df) <- "elevation"
    }
    locations<-sp::SpatialPointsDataFrame(sp::coordinates(locations[,1:2]),
                             proj4string = sp::CRS(SRS_string = prj$wkt),
                             data = df)
  } else if(class(locations) == "SpatialPoints"){
    if(is.null(sp::wkt(locations))& is.na(prj)){
      stop("Please supply a valid crs.")
    }
    
    if(is.null(sp::wkt(locations))){
      locations <- sp::SpatialPoints(locations, proj4string = sp::CRS(SRS_string = prj$wkt))
    }
    locations<-sp::SpatialPointsDataFrame(locations,
                                          data = data.frame(elevation = 
                                                              vector("numeric",
                                                                     nrow(sp::coordinates(locations)))))
  } else if(class(locations) == "SpatialPointsDataFrame"){
    if(is.null(sp::wkt(locations)) & is.na(prj)) {
      stop("Please supply a valid crs.")
    }
    if(is.null(sp::wkt(locations))){
      locations <- sp::SpatialPoints(locations, proj4string = sp::CRS(SRS_string = prj$wkt))
    }
    locations@data <- data.frame(locations@data,
                                 elevation = vector("numeric",nfeature)) 
  } else if(attributes(class(locations)) %in% c("raster","sp")){
    
    if(attributes(class(locations)) %in% "raster"){
      locs <- raster::crs(locations)
    } else {
      locs <- sp::wkt(locations)
    }
    if((is.null(locs) | 
       is.na(locs)) & is.na(prj)){
      stop("Please supply a valid crs.")
    }
    if(is.null(locs) |
       is.na(locs)){
        if(attributes(class(locations)) == "raster"){
          if(sum(!is.na(raster::getValues(locations))) == 0){
            stop("No distinct points, all values NA.")
          } else {
            locations <- raster::rasterToPoints(locations,spatial = TRUE)
            sp::SpatialPoints(locations, proj4string = sp::CRS(SRS_string = prj$wkt))
          }
        } else {
          sp::proj4string(locations)<-prj
        }
    } else if(attributes(class(locations)) %in% c("raster")){
      locations <- raster::rasterToPoints(locations,spatial = TRUE)
    }
  }
locations
} 



#' function to project bounding box and if needed expand it
#' @keywords internal
proj_expand <- function(locations,prj,expand){

  lll <- grepl("GEOGCRS",prj) |
    grepl("GEODCRS",prj) |
    grepl("GEODETICCRS",prj) |
    grepl("GEOGRAPHICCRS",prj) 
  
  if(is.null(nrow(locations))){
    nfeature <- length(locations) 
  } else {
    nfeature <- nrow(locations)
  }
  
  if(any(sp::bbox(locations)[2,] == 0) & lll & is.null(expand)){
    # Edge case for lat exactly at the equator - was returning NA
    expand <- 0.01
  } else if(nfeature == 1 & lll & is.null(expand)){
    # Edge case for single point and lat long
    expand <- 0.01
  } else if(nfeature == 1 & is.null(expand)){
    # Edge case for single point and projected
    expand <- 1
  }
 
  bbx <- bbox_to_sp(sp::bbox(locations), prj = prj)
  
  if(!is.null(expand)){
    bbx <- methods::as(sf::st_buffer(sf::st_as_sf(bbx), expand), "Spatial")
  }
  
  bbx <- sp::bbox(sp::spTransform(bbx, sp::CRS(ll_geo)))
  bbx
  
}

#' function to clip the DEM
#' @keywords internal
clip_it <- function(rast, loc, expand, clip){
  loc_wm <- sp::spTransform(loc, raster::crs(rast))
  if(clip == "locations" & !grepl("Points", class(loc_wm))){
    dem <- raster::mask(raster::crop(rast,loc_wm), loc_wm)
  } else if(clip == "bbox" | grepl("Points", class(loc_wm))){
    bbx <- proj_expand(loc_wm, as.character(raster::crs(rast)), expand)
    bbx_sp <- sp::spTransform(bbox_to_sp(bbx), raster::crs(rast))
    dem <- raster::mask(raster::crop(rast,bbx_sp), bbx_sp)
  }
  dem
}

#' Edited from https://github.com/jhollist/quickmapr/blob/master/R/internals.R
#' Assumes geographic projection
#' sp bbox to poly
#' @param bbx an sp bbox object
#' @param prj defaults to "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"
#' @keywords internal
#' @importFrom sp wkt
bbox_to_sp <- function(bbox, prj = sp::wkt(sp::CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))) {
  x <- c(bbox[1, 1], bbox[1, 1], bbox[1, 2], bbox[1, 2], bbox[1, 1])
  y <- c(bbox[2, 1], bbox[2, 2], bbox[2, 2], bbox[2, 1], bbox[2, 1])
  p <- sp::Polygon(cbind(x, y))
  ps <- sp::Polygons(list(p), "p1")
  sp_bbx <- sp::SpatialPolygons(list(ps), 1L, proj4string = sp::CRS(prj))
  sp_bbx
}

#' Estimate download size of DEMs
#' @param locations the locations
#' @param src the src
#' @param z zoom level if source is aws
#' @keywords internal
#' @importFrom sp wkt
estimate_raster_size <- function(locations, src, z = NULL){
  
  locations <- bbox_to_sp(sp::bbox(locations), 
                          prj = sp::wkt(locations))
  #locations <- sp::spTransform(locations, sp::CRS("+init=EPSG:4326"))
  locations <- sp::spTransform(locations, sp::CRS("+proj=longlat +datum=WGS84 +no_defs"))
  # Estimated cell size from zoom level source
  # https://github.com/tilezen/joerd/blob/master/docs/data-sources.md#sources-native-resolution
  z_res <- data.frame(z = 0:14, res_dd = c(0.54905236, 0.27452618, 0.15455633, 
                                           0.07145545, 0.03719130, 0.01901903, 
                                           0.00962056, 0.00483847, 0.00241219, 
                                           0.00120434, 0.00060173, 0.00030075, 
                                           0.00015035, 0.00007517, 0.00003758))

  bits <- switch(src,
                 aws = 32,
                 gl3 = 32,
                 gl1 = 32,
                 alos = 32,
                 srtm15plus = 32)
  if(src == "aws"){
    res <- z_res[z_res$z == z,]$res_dd
  } else{
    res <- switch(src,
                  gl3 = 0.0008333,
                  gl1 = 0.0002778,
                  alos = 0.0002778,
                  srtm15plus = 0.004165) 
  }
  num_rows <- (sp::bbox(locations)[1, "max"] - sp::bbox(locations)[1, "min"])/res
  num_cols <- (sp::bbox(locations)[2, "max"] - sp::bbox(locations)[2, "min"])/res
  
  num_megabytes <- (num_rows * num_cols * bits)/8388608
  num_megabytes
}
