## ======================================================================
## Shiny App: HydroTemp OS – RPI Sensor Dashboard
## CodeMonkey: Mike Proctor
## ======================================================================

source("Setup.R")
library(fuzzyjoin)
library(lubridate)

# ── 1. Data ingest & cleaning ────────────────────────────────────────────────

replace_iqr_outliers <- function(x) {
  q   <- quantile(x, probs = c(0.25, 0.75), na.rm = TRUE)
  iqr <- q[2] - q[1]
  if_else(x >= q[1] - 1.5 * iqr & x <= q[2] + 1.5 * iqr, x, NA_real_)
}

OnBoard <- read_csv(here(source_path, "OnBoard.log"),
                    col_names      = FALSE,
                    show_col_types = FALSE)

RPI <- OnBoard |>
  mutate(
    DateTime_RPI = as.POSIXct(paste0(X1, X2), tz = "UTC") |>
      lubridate::with_tz("America/Chicago")
  ) |>
  rename(RPI_Temp = X3, Fan = X4) |>
  select(-X1, -X2) |>
  separate(Fan, into = c(NA, "Fan"), sep = "[:]") |>
  mutate(
    Fan        = trimws(Fan),
    Fan_Status = as.numeric(Fan == "ON"),  # 0 / 1 for plotting
    RPI_Temp   = as.numeric(gsub("F$", "", trimws(RPI_Temp)))  # strip "F" suffix
  )

# 23 rows have fewer than 5 columns (sensor dropout) - read_csv fills the
# missing columns with NA, which is intentional. suppressWarnings() prevents
# the "X columns, expected 5" notice from stopping the Shiny launch.
Temps <- suppressWarnings(
  read_csv(here(source_path, "templog.csv"), show_col_types = FALSE)
)

Sensors <- Temps |>
  rename(
    DateTime     = Timestamp,
    Soil_Surface = `Bad Sensor`,
    Soil_4       = `Soil Temp 4`
  ) |>
  mutate(
    Soil_Surface = if_else(Soil_Surface <= 105, Soil_Surface, NA_real_),
    across(c(Soil_4, Enclosure, Ambient), replace_iqr_outliers)
  )

AllTemps <- Sensors %>%
  difference_inner_join(
    RPI,
    by       = c("DateTime" = "DateTime_RPI"),
    max_dist = 240
  )

# ── 2. Sensor metadata (display label, colour) ───────────────────────────────

sensor_meta <- tibble::tribble(
  ~col,          ~label,          ~colour,
  "Soil_4",      "Soil 4",        "brown",
  "Soil_Surface","Soil Surface",  "green",
  "Ambient",     "Ambient",       "red",
  "Enclosure",   "Enclosure",     "aquamarine",
  "RPI_Temp",    "RPI Temp",      "deeppink3",
  "Fan_Status",  "Fan Status",    "blue"   
)

date_range <- range(AllTemps$DateTime, na.rm = TRUE)

# ── 3. UI ─────────────────────────────────────────────────────────────────────

ui <- fluidPage(

  titlePanel("HydroTemp OS – FlatBroke Farms"),

  sidebarLayout(

    sidebarPanel(
      width = 3,

      h4("Sensors"),
      checkboxGroupInput(
        inputId  = "sensors",
        label    = NULL,
        choices  = setNames(sensor_meta$col, sensor_meta$label),
        selected = sensor_meta$col
      ),

      hr(),

      h4("Date Range"),
      sliderInput(
        inputId    = "date_range",
        label      = NULL,
        min        = as.Date(date_range[1]),
        max        = as.Date(date_range[2]),
        value      = c(as.Date(date_range[1]), as.Date(date_range[2])),
        timeFormat = "%b %d",
        step       = 1
      )
    ),

    mainPanel(
      width = 9,
      plotlyOutput("temp_plot", height = "550px")
    )
  )
)

# ── 4. Server ─────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  df_filtered <- reactive({
    req(input$date_range)
    AllTemps |>
      filter(
        as.Date(DateTime) >= input$date_range[1],
        as.Date(DateTime) <= input$date_range[2]
      )
  })

  output$temp_plot <- renderPlotly({

    df  <- df_filtered()
    sel <- input$sensors

    # Separate Fan_Status (overlay) from the regular temperature sensors
    show_fan  <- "Fan_Status" %in% sel
    meta_temp <- sensor_meta |> filter(col %in% sel, col != "Fan_Status")

    if (nrow(meta_temp) == 0 && !show_fan) {
      return(
        plotly_empty() |>
          layout(title = "No sensors selected.")
      )
    }

    # Pivot temperature sensors to long format -- one geom_line, correct colours
    df_long <- df |>
      select(DateTime, all_of(meta_temp$col)) |>
      pivot_longer(
        cols      = -DateTime,
        names_to  = "col",
        values_to = "value"
      ) |>
      left_join(meta_temp, by = "col") |>
      mutate(label = factor(label, levels = meta_temp$label))

    # Fan ON overlay: RPI_Temp kept only where Fan_Status == 1, NA elsewhere.
    # Gated on the "Fan Status" checkbox in input$sensors.
    fan_label  <- "Fan ON (RPI Temp)"
    fan_colour <- sensor_meta |> filter(col == "Fan_Status") |> pull(colour)

    df_fan <- if (show_fan) {
      df |>
        mutate(
          .keep  = "none",
          DateTime,
          col    = "Fan_ON",
          value  = if_else(Fan_Status == 1, RPI_Temp, NA_real_),
          label  = fan_label,
          colour = fan_colour
        )
    } else {
      NULL
    }

    # Build combined colour lookup
    all_colours <- setNames(meta_temp$colour, meta_temp$label)
    all_levels  <- levels(df_long$label)

    if (show_fan) {
      all_colours <- c(all_colours, setNames(fan_colour, fan_label))
      all_levels  <- c(all_levels, fan_label)
    }

    df_combined <- bind_rows(
      df_long |> mutate(label = as.character(label)),
      df_fan
    ) |>
      mutate(label = factor(label, levels = all_levels))

    p <- ggplot(df_combined, aes(x = DateTime, y = value, colour = label)) +
      geom_line(na.rm = TRUE) +
      scale_colour_manual(
        name   = "Sensor",
        values = all_colours
      ) +
      labs(
        title = "HydroTemp OS -- FlatBroke Farms",
        x     = NULL,
        y     = "Temperature (F)"
      ) +
      theme_minimal(base_size = 14) +
      theme(legend.position = "right")

    ggplotly(p, tooltip = c("x", "y", "colour")) |>
      layout(legend = list(orientation = "v"))
  })
}

# ── 5. Run ────────────────────────────────────────────────────────────────────

shinyApp(ui, server)
