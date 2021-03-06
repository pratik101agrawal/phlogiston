#!/usr/bin/env Rscript
# Graph Phlogiston csv reports as charts

library(ggplot2)
library(scales)
library(RColorBrewer)
library(ggthemes)
library(argparse)
library(reshape)

suppressPackageStartupMessages(library("argparse"))
parser <- ArgumentParser()

parser$add_argument("scope_prefix", nargs=1, help="Scope prefix")
parser$add_argument("tranche_num", nargs=1, help="Tranche Number")
parser$add_argument("color", nargs=1, help="Color")
parser$add_argument("tranche_name", nargs=1, help="Tranche Name")
parser$add_argument("report_date", nargs=1, help="Date of report")
parser$add_argument("chart_start", nargs=1)
parser$add_argument("chart_end", nargs=1)
parser$add_argument("current_quarter_start", nargs=1)
parser$add_argument("next_quarter_start", nargs=1)

args <- parser$parse_args()

# TODO: confirm this isn't used and remove it from here and upstream
#velocity_recent_date <- read.csv(sprintf("/tmp/%s/velocity_recent_date.csv", args$scope_prefix))
#velocity_recent_date$date <- as.Date(velocity_recent_date$date, "%Y-%m-%d")

report_date <- as.Date(args$report_date)
chart_start <- as.Date(args$chart_start)
chart_end   <- as.Date(args$chart_end)
current_quarter_start  <- as.Date(args$current_quarter_start)
next_quarter_start    <- as.Date(args$next_quarter_start)

# common theme from https://github.com/Ironholds/wmf/blob/master/R/dataviz.R
theme_fivethirtynine <- function(base_size = 12, base_family = "sans"){
  (theme_foundation(base_size = base_size, base_family = base_family) +
     theme(line = element_line(), rect = element_rect(fill = ggthemes::ggthemes_data$fivethirtyeight["ltgray"],
                                                      linetype = 0, colour = NA),
           text = element_text(size=10, colour = ggthemes::ggthemes_data$fivethirtyeight["dkgray"]),
           axis.title.y = element_text(size = rel(2), angle = 90, vjust = 1.5), 
           axis.title.x = element_text(size = rel(2)),
           axis.text = element_text(size=rel(1.8)),
           axis.ticks = element_blank(), axis.line = element_blank(),
           panel.grid = element_line(colour = NULL),
           panel.grid.major = element_line(colour = ggthemes_data$fivethirtyeight["medgray"]),
           panel.grid.minor = element_blank(),
           plot.title = element_text(hjust = 0, size = rel(2), face = "bold"),
           strip.background = element_rect()))
}

######################################################################
## Velocity
######################################################################
velocity_t <- read.csv(sprintf("/tmp/%s/tranche_velocity.csv", args$scope_prefix))
velocity_cat_t <- velocity_t[velocity_t$category == args$tranche_name,]
velocity_cat_t$date <- as.Date(velocity_cat_t$date, "%Y-%m-%d")

velocity_points <- read.csv(sprintf("/tmp/%s/tranche_velocity_points.csv", args$scope_prefix))
velocity_cat_points <- velocity_points[velocity_points$category == args$tranche_name,]
velocity_cat_points$date <- as.Date(velocity_cat_points$date, "%Y-%m-%d")

png(filename = sprintf("~/html/%s_tranche%s_velocity_points.png", args$scope_prefix, args$tranche_num), width=1000, height=300, units="px", pointsize=10)

ggplot(velocity_cat_points) +
  geom_line(aes(x=date, y=pes_points_vel), size=3, color="darkorange2") +
  geom_line(aes(x=date, y=opt_points_vel), size=3, color="chartreuse3") +
  geom_line(aes(x=date, y=nom_points_vel), size=2, color="gray") +
  geom_bar(data=velocity_cat_t, aes(x=date, y=points), fill="black", size=2, stat="identity") +
  labs(title=sprintf("%s velocity forecasts", args$tranche_name), y="Story Point Total") +
  scale_x_date(limits=c(chart_start, chart_end), date_minor_breaks="1 week", label=date_format("%b %d\n%Y"))+
  theme_fivethirtynine() +
  theme(axis.title.x=element_blank())
dev.off()

velocity_count <- read.csv(sprintf("/tmp/%s/tranche_velocity_count.csv", args$scope_prefix))
velocity_cat_count <- velocity_count[velocity_count$category == args$tranche_name,]
velocity_cat_count$date <- as.Date(velocity_cat_count$date, "%Y-%m-%d")

png(filename = sprintf("~/html/%s_tranche%s_velocity_count.png", args$scope_prefix, args$tranche_num), width=1000, height=300, units="px", pointsize=10)

ggplot(velocity_cat_count) +
  geom_line(aes(x=date, y=pes_count_vel), size=3, color="darkorange2") +
  geom_line(aes(x=date, y=opt_count_vel), size=3, color="chartreuse3") +
  geom_line(aes(x=date, y=nom_count_vel), size=2, color="gray") +
  geom_bar(data=velocity_cat_t, aes(x=date, y=count), fill="black", size=2, stat="identity") +
  labs(title=sprintf("%s velocity forecasts", args$tranche_name), y="Story Count") +
  scale_x_date(limits=c(chart_start, chart_end), date_minor_breaks="1 week", label=date_format("%b %d\n%Y"))+
  theme_fivethirtynine() +
  theme(axis.title.x=element_blank())
dev.off()

######################################################################
## Forecast
######################################################################

forecast <- read.csv(sprintf("/tmp/%s/forecast.csv", args$scope_prefix))
forecast$date <- as.Date(forecast$date, "%Y-%m-%d")
forecast <- forecast[forecast$category == args$tranche_name,]
forecast_opt_points <- forecast[ is.na(forecast$opt_points_fore) == 0,]
forecast_nom_points <- forecast[ is.na(forecast$nom_points_fore) == 0,]
forecast_pes_points <- forecast[ is.na(forecast$pes_points_fore) == 0,]
forecast_opt_count <- forecast[ is.na(forecast$opt_count_fore) == 0,]
forecast_nom_count <- forecast[ is.na(forecast$nom_count_fore) == 0,]
forecast_pes_count <- forecast[ is.na(forecast$pes_count_fore) == 0,]

png(filename = sprintf("~/html/%s_tranche%s_forecast_points.png", args$scope_prefix, args$tranche_num), width=1000, height=300, units="px", pointsize=10)

p <- ggplot(forecast) +
  labs(title=sprintf("%s completion forecast by points", args$tranche_name), y="weeks remaining") +
  scale_x_date(limits=c(chart_start, chart_end), date_minor_breaks="1 week", label=date_format("%b %d\n%Y")) +
  scale_y_continuous(limits=c(0,14), breaks=pretty_breaks(n=7), oob=squish) +
  theme_fivethirtynine() +
  theme(legend.title=element_blank())

if(nrow(forecast_pes_points) > 0) {
  p = p + geom_line(aes(x=date, y=pes_points_fore), color="darkorange2", size=3)
}

if(nrow(forecast_opt_points) > 0) {
  p = p + geom_line(aes(x=date, y=opt_points_fore), color="chartreuse3", size=3)
}

if(nrow(forecast_nom_points) > 0) {
  p = p + geom_line(aes(x=date, y=nom_points_fore), color="gray", size=2)
}

p
dev.off()

png(filename = sprintf("~/html/%s_tranche%s_forecast_count.png", args$scope_prefix, args$tranche_num), width=1000, height=300, units="px", pointsize=10)

p <- ggplot(forecast) +
  labs(title=sprintf("%s completion forecast by count", args$tranche_name), y="weeks remaining") +
  scale_x_date(limits=c(chart_start, chart_end), date_minor_breaks="1 week", label=date_format("%b %d\n%Y"))+
  scale_y_continuous(limits=c(0,14), breaks=pretty_breaks(n=7), oob=squish ) +
  theme_fivethirtynine() +
  theme(legend.title=element_blank())

if(nrow(forecast_pes_count) > 0) {
  p = p + geom_line(aes(x=date, y=pes_count_fore), color="darkorange2", size=3)
}

if(nrow(forecast_opt_count) > 0) {
  p = p + geom_line(aes(x=date, y=opt_count_fore), color="chartreuse3", size=3)
}

if(nrow(forecast_nom_count) > 0) {
  p = p +  geom_line(aes(x=date, y=nom_count_fore), color="gray", size=2)
}

p
dev.off()

######################################################################
## Burnup
######################################################################
backlog <- read.csv(sprintf("/tmp/%s/backlog.csv", args$scope_prefix))
backlog <- backlog[backlog$category==args$tranche_name,]
backlog$date <- as.Date(backlog$date, "%Y-%m-%d")

burnup_cat <- read.csv(sprintf("/tmp/%s/burnup_categories.csv", args$scope_prefix))
burnup_cat <- burnup_cat[burnup_cat$category==args$tranche_name,]
burnup_cat$date <- as.Date(burnup_cat$date, "%Y-%m-%d")

forecast <- forecast[forecast$date >= report_date,]
forecast_current <- na.omit(forecast[ forecast$weeks_old < 1 & forecast$weeks_old >= 0 & forecast$count_resolved > 0,])
forecast_current$opt_count_date <- as.Date(forecast_current$opt_count_date, "%Y-%m-%d")

png(filename = sprintf("~/html/%s_tranche%s_burnup_points.png", args$scope_prefix, args$tranche_num), width=1000, height=700, units="px", pointsize=10)
ggplot(backlog) +
  labs(title=sprintf("%s burnup by points", args$tranche_name), y="Story Point Total") +
  theme_fivethirtynine() +
  theme(legend.title=element_blank(), axis.title.x=element_blank()) +
  scale_x_date(limits=c(chart_start, chart_end), date_minor_breaks="1 week", label=date_format("%b %d\n%Y")) +
  annotate("rect", xmin=current_quarter_start, xmax=next_quarter_start, ymin=0, ymax=Inf, fill="white", alpha=0.5) +
  geom_area(position='stack', aes(x = date, y = points, ymin=0), fill=args$color) +
  geom_line(data=burnup_cat, aes(x=date, y=points), size=2) +
  geom_line(data=forecast, aes(x=date, y=pes_points_velviz), color="black", linetype=3, size=1) +
  geom_line(data=forecast, aes(x=date, y=nom_points_velviz), color="black", linetype=2, size=2) +
  geom_line(data=forecast, aes(x=date, y=opt_points_velviz), color="black", linetype=3, size=1) +
  geom_line(data=forecast, aes(x=date, y=pes_points_growviz), color="gray", linetype=3, alpha=0.8, size=1) +
  geom_line(data=forecast, aes(x=date, y=nom_points_growviz), color="gray", linetype=2, alpha=0.8, size=3) +
  geom_line(data=forecast, aes(x=date, y=opt_points_growviz), color="gray", linetype=3, alpha=0.8, size=1)
dev.off()

png(filename = sprintf("~/html/%s_tranche%s_burnup_count.png", args$scope_prefix, args$tranche_num), width=1000, height=700, units="px", pointsize=10)

p <- ggplot(backlog) +
  labs(title=sprintf("%s burnup by count", args$tranche_name), y="Story Count") +
  theme_fivethirtynine() +
  theme(legend.title=element_blank(), axis.title.x=element_blank()) +
  scale_x_date(limits=c(chart_start, chart_end), label=date_format("%b %d\n%Y")) +
  annotate("rect", xmin=current_quarter_start, xmax=next_quarter_start, ymin=0, ymax=Inf, fill="white", alpha=0.5) +
  geom_area(position='stack', aes(x = date, y = count, ymin=0), fill=args$color) +
  geom_line(data=burnup_cat, aes(x=date, y=count), size=2) +
  geom_line(data=forecast, aes(x=date, y=pes_count_velviz), color="black", linetype=3, size=1) +
  geom_line(data=forecast, aes(x=date, y=nom_count_velviz), color="black", linetype=2, size=2) +
  geom_line(data=forecast, aes(x=date, y=opt_count_velviz), color="black", linetype=3, size=1) +
  geom_line(data=forecast, aes(x=date, y=pes_count_growviz), color="gray", linetype=3, alpha=0.8, size=1) +
  geom_line(data=forecast, aes(x=date, y=nom_count_growviz), color="gray", linetype=2, alpha=0.8, size=3) +
  geom_line(data=forecast, aes(x=date, y=opt_count_growviz), color="gray", linetype=3, alpha=0.8, size=1)

if(nrow(forecast_current) > 0) {
  p = p + annotate("segment",
                   x=forecast_current$opt_count_date,
                   xend=forecast_current$opt_count_date,
                   y=0,
                   yend=forecast_current$opt_count_velviz) +
  annotate("text", x=forecast_current$opt_count_date, y=0, label=forecast_current$opt_count_date)
}

p
dev.off()
