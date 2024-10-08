#' @title Interact with batchLLM via a Shiny Gadget
#'
#' @description This function provides a user interface using Shiny to interact with
#' the `batchLLM` package. It allows users to configure and execute batch processing
#' through an interactive dashboard.
#' 
#' @return No return value. Launches a Shiny Gadget that allows users to interact with the `batchLLM` package.
#'
#' @importFrom shiny fluidPage fluidRow column titlePanel tabPanel tabsetPanel
#' @importFrom shiny conditionalPanel HTML sidebarLayout sidebarPanel mainPanel
#' @importFrom shiny textInput numericInput downloadButton updateTextInput
#' @importFrom shiny tags tagList br hr h1 p span img uiOutput textAreaInput
#' @importFrom shiny sliderInput actionButton icon observe req
#' @importFrom shiny downloadHandler outputOptions selectInput updateSelectInput
#' @importFrom shiny renderUI observeEvent runGadget paneViewer fileInput
#' @importFrom shiny showNotification reactive reactiveVal
#' @importFrom shinydashboard dashboardPage dashboardHeader dashboardSidebar
#' @importFrom shinydashboard sidebarMenu menuItem dashboardBody tabItems tabItem
#' @importFrom shinydashboard box
#' @importFrom shinyWidgets pickerInput updatePickerInput radioGroupButtons
#' @importFrom DT dataTableOutput renderDataTable datatable
#' @importFrom shinyjs useShinyjs toggle hidden show hide
#' @importFrom rlang sym eval_tidy
#' @importFrom digest digest
#' @importFrom spsComps shinyCatch bsTooltip
#' @importFrom readr read_csv
#' @importFrom readxl read_excel
#' @importFrom tools file_ext file_path_sans_ext
#' @importFrom stats setNames
#' @importFrom jsonlite write_json
#' @import batchLLM
#' @export
batchLLM_shiny <- function() {
  df_objects <- "beliefs"

  create_exportable_datatable <- function(data, filename_prefix) {
    datatable(
      data,
      extensions = c("Buttons"),
      options = list(
        scrollX = T,
        dom = "Blfrtip",
        buttons = list(
          list(
            extend = "collection",
            buttons = list(
              list(
                extend = "csv", filename = paste0(filename_prefix, "_export"),
                exportOptions = list(modifier = list(page = "all"))
              ),
              list(
                extend = "excel", filename = paste0(filename_prefix, "_export"),
                exportOptions = list(modifier = list(page = "all"))
              ),
              list(
                extend = "pdf", filename = paste0(filename_prefix, "_export"),
                exportOptions = list(modifier = list(page = "all"))
              )
            ),
            text = "Download"
          )
        ),
        pageLength = 10,
        lengthMenu = list(c(10, 25, 50, -1), c("10", "25", "50", "All"))
      )
    )
  }

  labelWithInfo <- function(label, tooltip) {
    tagList(
      span(label),
      span(
        style = "margin-left: 5px;",
        icon("info-circle") |>
          bsTooltip(tooltip, placement = "right")
      )
    )
  }

  ui <- dashboardPage(
    skin = "black",
    dashboardHeader(title = "batchLLM"),
    dashboardSidebar(
      sidebarMenu(
        id = "tabs",
        menuItem("Home", tabName = "home", icon = icon("home")),
        menuItem("Run Batches", tabName = "run_batches", icon = icon("table")),
        menuItem("Get Batches", tabName = "get_batches", icon = icon("list-ol")),
        menuItem("Download Log", tabName = "download_log", icon = icon("download"))
      )
    ),
    dashboardBody(
      useShinyjs(),
      tabItems(
        tabItem(
          tabName = "home",
          fluidRow(
            column(
              width = 12,
              box(
                width = 12,
                solidHeader = TRUE,
                tags$div(
                  img(src = "https://raw.githubusercontent.com/dylanpieper/batchLLM/main/inst/batchLLM_hexLogo.png", height = "200px"),
                  h1("Welcome!"),
                  p("Batch process large language model (LLM) text completions by looping across the rows of a data frame column. The package currently supports OpenAI's GPT, Anthropic's Claude, and Google's Gemini models, with built-in delays for API rate limiting. The package provides advanced text processing features, including automatic logging of batches and metadata to local files, side-by-side comparison of outputs from different LLMs, and integration of a user-friendly Shiny App Addin. Use cases include natural language processing tasks such as sentiment analysis, thematic analysis, classification, labeling or tagging, and language translation."),
                  br(),
                  tags$a(
                    href = "https://platform.openai.com/login?launch",
                    target = "_blank",
                    icon("key"),
                    "OpenAI"
                  ),
                  tags$a(
                    href = "https://console.anthropic.com/",
                    target = "_blank",
                    icon("key"),
                    "Anthropic"
                  ),
                  tags$a(
                    href = "https://gemini.google.com/",
                    target = "_blank",
                    icon("key"),
                    "Google Gemini"
                  ),
                  br(), br(),
                  tags$a(
                    href = "https://github.com/dylanpieper/batchLLM",
                    target = "_blank",
                    icon("github"),
                    "GitHub Source Code"
                  )
                )
              )
            )
          )
        ),
        tabItem(
          tabName = "run_batches",
          fluidRow(
            column(
              width = 4,
              box(
                width = NULL,
                title = "Upload Data",
                solidHeader = TRUE,
                fileInput("datafile", "Choose CSV or Excel File", accept = c(".csv", ".xlsx"))
              ),
              box(
                width = NULL,
                title = "Configure batchLLM",
                solidHeader = TRUE,
                pickerInput(
                  inputId = "df_name",
                  label = "Data:",
                  choices = df_objects,
                  options = list(`live-search` = TRUE)
                ),
                uiOutput("col_name_ui"),
                textAreaInput(
                  inputId = "prompt",
                  label = "System Prompt:",
                  placeholder = "e.g., classify as a fact or misinformation in one word",
                  rows = 1
                ),
                uiOutput("llm_configs"),
                actionButton(
                  inputId = "add_llm_config",
                  label = "Add LLM"
                ),
                br(), br(),
                uiOutput("api_key_inputs"),
                radioGroupButtons(
                  inputId = "toggle_delay",
                  label = labelWithInfo("Batch Delay:", "Delay between batches. Random is an average of 10.86 seconds."),
                  choices = c("Random" = "random", "30 Sec" = "30sec", "1 Min" = "1min"),
                  selected = "random",
                  justified = TRUE
                ),
                numericInput(
                  inputId = "batch_size",
                  label = labelWithInfo("Batch Size:", "Number of rows processed per batch."),
                  value = 10,
                  min = 1,
                  step = 1
                ),
                radioGroupButtons(
                  inputId = "case_convert",
                  label = "Convert Text Case:",
                  choices = c("None" = "none", "Uppercase" = "upper", "Lowercase" = "lower"),
                  selected = "none",
                  justified = TRUE
                ),
                radioGroupButtons(
                  inputId = "sanitize",
                  label = labelWithInfo("Sanitize Output:", "Requests a response in XML tags and removes unwanted text (e.g., preamble) and all punctuation. May produce an unintended XML structure in longer responses."),
                  choices = c("False" = "FALSE", "True" = "TRUE"),
                  selected = "FALSE",
                  justified = TRUE
                ),
                actionButton(
                  inputId = "run_batchLLM",
                  label = "Run batchLLM"
                )
              )
            ),
            column(
              width = 8,
              box(
                width = NULL,
                title = "Viewer",
                solidHeader = TRUE,
                tabsetPanel(
                  tabPanel("Data", DT::dataTableOutput("data_results")),
                  tabPanel("Metadata", DT::dataTableOutput("metadata_table"))
                )
              )
            )
          )
        ),
        tabItem(
          tabName = "get_batches",
          fluidRow(
            box(
              width = 12,
              title = "Get Batches",
              solidHeader = TRUE,
              selectInput("batch_select", "Select Data:", choices = NULL),
              actionButton("refresh_batches", "Refresh"),
              hr(),
              DT::dataTableOutput("batch_table")
            )
          )
        ),
        tabItem(
          tabName = "download_log",
          fluidRow(
            box(
              width = 12,
              title = "Download Log",
              solidHeader = TRUE,
              tabItem(
                tabName = "download_log",
                fluidRow(
                  box(
                    width = 12,
                    solidHeader = TRUE,
                    conditionalPanel(
                      condition = "output.log_file_exists",
                      downloadButton("download_rds", "Download RDS"),
                      downloadButton("download_json", "Download JSON")
                    ),
                    conditionalPanel(
                      condition = "!output.log_file_exists",
                      p("No log file available for download.")
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )

  server <- function(input, output, session) {
    if (!exists("beliefs")) {
      session$userData$beliefs <- batchLLM::beliefs
    }

    all_objects <- reactiveVal(c())

    observe({
      req(input$datafile)

      current_objects <- c(ls(envir = .GlobalEnv), ls(envir = session$userData))
      all_objects(current_objects)

      df_objects <- Filter(function(x) {
        obj <- if (exists(x, envir = session$userData)) {
          get(x, envir = session$userData)
        } else {
          get(x, envir = .GlobalEnv)
        }
        is.data.frame(obj) || inherits(obj, "data.frame")
      }, current_objects)

      updatePickerInput(
        session = session,
        inputId = "df_name",
        choices = df_objects
      )
    })

    observeEvent(input$datafile, {
      req(input$datafile)
      file <- input$datafile$datapath
      ext <- file_ext(file)
      df <- switch(ext,
        csv = readr::read_csv(file),
        xlsx = readxl::read_excel(file),
        showNotification("Invalid file. Please upload a .csv or .xlsx file.", type = "error")
      )
      df_name <- file_path_sans_ext(input$datafile$name)
      session$userData[[df_name]] <- df
      updatePickerInput(
        session = session,
        inputId = "df_name",
        choices = c(all_objects(), df_name),
        selected = df_name
      )
      message("Data file loaded successfully")
    })

    llm_configs <- reactiveVal(list())
    next_id <- reactiveVal(1)

    observeEvent(input$add_llm_config, {
      current_configs <- llm_configs()
      new_id <- next_id()

      new_config <- list(
        id = paste0("Config-", new_id),
        llm = NULL,
        model = NULL,
        temperature = 0.5
      )

      llm_configs(c(current_configs, list(new_config)))
      next_id(new_id + 1)
    })

    output$llm_configs <- renderUI({
      lapply(llm_configs(), function(config) {
        box(
          width = NULL,
          title = config$id,
          pickerInput(
            inputId = paste0(config$id, "_llm"),
            label = "LLM:",
            choices = c("OpenAI" = "openai", "Anthropic" = "anthropic", "Google" = "gemini")
          ),
          pickerInput(
            inputId = paste0(config$id, "_model"),
            label = "Model:",
            choices = NULL
          ),
          sliderInput(
            inputId = paste0(config$id, "_temperature"),
            label = "Temperature:",
            min = 0,
            max = 1,
            value = config$temperature,
            step = 0.1
          ),
          sliderInput(
            inputId = paste0(config$id, "_max_tokens"),
            label = "Maximum Tokens:",
            min = 100,
            max = 4000,
            value = 500,
            step = 50
          ),
          actionButton(
            inputId = paste0("remove_", config$id),
            label = "Remove LLM"
          )
        )
      })
    })

    output$api_key_inputs <- renderUI({
      req(length(llm_configs()) > 0)

      unique_llms <- unique(sapply(llm_configs(), function(config) input[[paste0(config$id, "_llm")]]))

      lapply(unique_llms, function(llm) {
        if (!is.null(llm)) {
          env_var_name <- paste0(toupper(llm), "_API_KEY")
          existing_key <- Sys.getenv(env_var_name)

          textInput(
            inputId = paste0(llm, "_api_key"),
            label = paste0(toupper(llm), " API KEY:"),
            value = existing_key,
            placeholder = paste("Enter your", toupper(llm), "API KEY")
          )
        }
      })
    })

    observe({
      lapply(llm_configs(), function(config) {
        observeEvent(input[[paste0(config$id, "_llm")]], {
          llm_name <- input[[paste0(config$id, "_llm")]]
          if (llm_name == "openai") {
            model_choices <- c(
              "GPT-4" = "gpt-4",
              "GPT-4o" = "gpt-4o",
              "GPT-4o Mini" = "gpt-4o-mini",
              "GPT-4 Turbo" = "gpt-4-turbo",
              "GPT-3.5 Turbo" = "gpt-3.5-turbo"
            )
          } else if (llm_name == "anthropic") {
            model_choices <- c(
              "Claude 3.5 Sonnet" = "claude-3-5-sonnet-20240620",
              "Claude 3 Opus" = "claude-3-opus-20240229",
              "Claude 3 Sonnet" = "claude-3-sonnet-20240229",
              "Claude 3 Haiku" = "claude-3-haiku-20240307",
              "Claude 2.1" = "claude-2.1",
              "Claude 2.0" = "claude-2.0"
            )
          } else if (llm_name == "gemini") {
            model_choices <- c(
              "Gemini 1.5 Pro" = "1.5-pro",
              "Gemini 1.5 Flash" = "1.5-flash",
              "Gemini 1 Pro" = "1.0-pro"
            )
          }
          updatePickerInput(
            session = session,
            inputId = paste0(config$id, "_model"),
            choices = model_choices
          )
        })

        observeEvent(input[[paste0("remove_", config$id)]], {
          current_configs <- llm_configs()
          updated_configs <- current_configs[!sapply(current_configs, function(x) x$id == config$id)]
          llm_configs(updated_configs)
        })
      })
    })

    output$col_name_ui <- renderUI({
      req(input$df_name)
      df <- if (exists(input$df_name, envir = session$userData)) {
        get(input$df_name, envir = session$userData)
      } else {
        get(input$df_name, envir = .GlobalEnv)
      }

      char_columns <- names(df)[sapply(df, is.character)]

      if (length(char_columns) == 0) {
        char_columns <- "No character columns available."
      }

      pickerInput(
        inputId = "col_name",
        label = "Column:",
        choices = char_columns,
        selected = if (length(char_columns) > 0) char_columns[1] else NULL
      )
    })

    selected_data <- reactive({
      req(input$df_name)
      if (exists(input$df_name, envir = session$userData)) {
        get(input$df_name, envir = session$userData)
      } else {
        get(input$df_name, envir = .GlobalEnv)
      }
    })

    observeEvent(input$datafile, {
      req(input$datafile)
      df <- selected_data()
      if (!is.null(df) && ncol(df) > 0) {
        updatePickerInput(
          session = session,
          inputId = "col_name",
          selected = names(df)[1]
        )
      }
    })

    metadata_trigger <- reactiveVal(0)

    current_metadata <- reactive({
      metadata_trigger()
      req(input$df_name, input$col_name)
      df <- selected_data()
      key <- digest::digest(df[[input$col_name]], algo = "crc32c")
      df_name_key <- paste0(input$df_name, "_", key)
      metadata <- scrape_metadata(df_name = df_name_key)
      if (is.null(metadata) || nrow(metadata) == 0) {
        return(data.frame(Message = "No metadata available."))
      }
      return(metadata)
    })

    observeEvent(input$tabs, {
      if (input$tabs == "metadata") {
        metadata_trigger(metadata_trigger() + 1)
      }
    })

    result <- reactiveVal(NULL)
    log_file_exists <- reactiveVal(FALSE)

    observeEvent(input$run_batchLLM, {
      req(input$df_name, input$col_name)

      if (is.null(input$col_name) || input$col_name == "") {
        showNotification("Please select a column from the dataset.", type = "error")
        return()
      }

      if (is.null(input$batch_size) || input$batch_size < 1) {
        showNotification("Please enter a valid batch size (> 1).", type = "error")
        return()
      }

      if (is.null(input$prompt) || trimws(input$prompt) == "") {
        showNotification("Please enter a system prompt.", type = "error")
        return()
      }

      configs <- llm_configs()
      if (length(configs) == 0) {
        showNotification("Please add at least one LLM configuration.", type = "error")
        return()
      }

      configs <- lapply(llm_configs(), function(config) {
        list(
          LLM = input[[paste0(config$id, "_llm")]],
          model = input[[paste0(config$id, "_model")]],
          temperature = input[[paste0(config$id, "_temperature")]],
          max_tokens = input[[paste0(config$id, "_max_tokens")]]
        )
      })

      missing_keys <- sapply(configs, function(config) {
        api_key_input <- input[[paste0(config$LLM, "_api_key")]]
        is.null(api_key_input) || api_key_input == ""
      })

      if (any(missing_keys)) {
        showNotification("Please enter API keys for all configurations.", type = "error")
        return()
      }

      shinyCatch(
        {
          df <- selected_data()

          for (config in configs) {
            env_var_name <- paste0(toupper(config$LLM), "_API_KEY")
            api_key <- input[[paste0(config$LLM, "_api_key")]]
            do.call("Sys.setenv", setNames(list(api_key), env_var_name))
          }

          for (config in configs) {
            df <- batchLLM(
              LLM = if (config$LLM == "gemini") "google" else config$LLM,
              df = df,
              df_name = input$df_name,
              col = !!sym(input$col_name),
              prompt = input$prompt,
              batch_delay = input$toggle_delay,
              batch_size = input$batch_size,
              sanitize = as.logical(input$sanitize),
              model = config$model,
              temperature = config$temperature,
              max_tokens = config$max_tokens,
              case_convert = input$case_convert
            )
          }
          if (file.exists("batchLLM-log.rds")) {
            log_file_exists(TRUE)
          }
          result(df)
          metadata_trigger(metadata_trigger() + 1)
        },
        prefix = ""
      )
    })

    observe({
      lapply(c("openai", "anthropic", "google"), function(llm) {
        observeEvent(input[[paste0(llm, "_api_key")]], {
          env_var_name <- paste0(toupper(llm), "_API_KEY")
          api_key <- input[[paste0(llm, "_api_key")]]
          do.call("Sys.setenv", setNames(list(api_key), env_var_name))
        })
      })
    })

    output$data_results <- renderDataTable(
      {
        data_to_show <- if (!is.null(input$datafile)) {
          selected_data()
        } else if (!is.null(result())) {
          result()
        } else {
          selected_data()
        }

        create_exportable_datatable(data_to_show, "data")
      },
      server = FALSE
    )

    output$metadata_table <- renderDataTable(
      {
        create_exportable_datatable(current_metadata(), "metadata")
      },
      server = FALSE
    )

    current_batch_data <- reactiveVal(NULL)

    update_batch_data <- function() {
      metadata <- scrape_metadata()
      batch_choices <- unique(metadata$df_name)
      updateSelectInput(session, "batch_select", choices = batch_choices)

      if (!is.null(input$batch_select) && input$batch_select %in% batch_choices) {
        batch_data <- get_batches(input$batch_select)
        current_batch_data(batch_data)
      } else if (length(batch_choices) > 0) {
        batch_data <- get_batches(batch_choices[1])
        current_batch_data(batch_data)
        updateSelectInput(session, "batch_select", selected = batch_choices[1])
      } else {
        current_batch_data(NULL)
      }
    }

    observeEvent(input$tabs,
      {
        if (input$tabs == "get_batches") {
          shinyCatch(
            {
              update_batch_data()
            },
            prefix = ""
          )
        }
      },
      ignoreInit = TRUE
    )

    observeEvent(input$refresh_batches, {
      shinyCatch(
        {
          update_batch_data()
          message("Batches were successfully refreshed.")
        },
        prefix = ""
      )
    })

    observeEvent(input$batch_select, {
      req(input$batch_select)
      batch_data <- get_batches(input$batch_select)
      current_batch_data(batch_data)
    })

    output$batch_table <- renderDataTable(
      {
        req(current_batch_data())
        create_exportable_datatable(current_batch_data(), "batch")
      },
      server = FALSE
    )

    observe({
      req(input$df_name)
      updateSelectInput(session, "col_name", selected = names(selected_data())[1])
    })

    output$log_file_exists <- reactive({
      log_file_exists()
    })

    outputOptions(output, "log_file_exists", suspendWhenHidden = FALSE)

    observe({
      output$download_log_tab <- renderUI({
        menuItem("Download Log", tabName = "download_log", icon = icon("download"))
      })
    })

    observe({
      observeEvent(input$datafile, {
        current_metadata()
      })
    })

    observe({
      if (log_file_exists()) {
        shinyjs::show("download_rds")
        shinyjs::show("download_json")
      } else {
        shinyjs::hide("download_rds")
        shinyjs::hide("download_json")
      }
    })

    output$download_log_tab <- renderUI({
      if (log_file_exists()) {
        menuItem("Download Log", tabName = "download_log", icon = icon("download"))
      }
    })

    output$download_rds <- downloadHandler(
      filename = function() {
        paste0("batchLLM-log-", Sys.Date(), ".rds")
      },
      content = function(file) {
        log_file <- "batchLLM-log.rds"
        if (file.exists(log_file)) {
          file.copy(log_file, file)
        } else {
          stop("No log file found to download.")
        }
      }
    )

    output$download_json <- downloadHandler(
      filename = function() {
        paste0("batchLLM-log-", Sys.Date(), ".json")
      },
      content = function(file) {
        log_file <- "batchLLM-log.rds"
        if (file.exists(log_file)) {
          log_data <- readRDS(log_file)
          write_json(log_data, path = file, pretty = TRUE, auto_unbox = TRUE)
        } else {
          stop("No log file found to download.")
        }
      }
    )
  }

  runGadget(ui, server, viewer = paneViewer())
}
