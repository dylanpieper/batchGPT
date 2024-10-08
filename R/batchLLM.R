#' @title Batch Process LLM Text Completions Using a Data Frame
#'
#' @description Batch process large language model (LLM) text completions by looping across the rows of a data frame column.
#' The package currently supports OpenAI's GPT, Anthropic's Claude, and Google's Gemini models, with built-in delays for API rate limiting.
#' The package provides advanced text processing features, including automatic logging of batches and metadata to local files, side-by-side comparison of outputs from different LLMs, and integration of a user-friendly Shiny App Addin.
#' Use cases include natural language processing tasks such as sentiment analysis, thematic analysis, classification, labeling or tagging, and language translation.
#'
#' @param df A data frame that contains the input data.
#' @param df_name An optional string specifying the name of the data frame to log. This is particularly useful in Shiny applications or when the data frame is passed programmatically rather than explicitly. Default is NULL.
#' @param col The name of the column in the data frame to process.
#' @param prompt A system prompt for the LLM model.
#' @param LLM A string for the name of the LLM with the options: "openai", "anthropic", and "google". Default is "openai".
#' @param model A string for the name of the model from the LLM. Default is "gpt-4o-mini".
#' @param temperature A temperature for the LLM model. Default is .5.
#' @param max_tokens A maximum number of tokens to generate before stopping. Default is 500.
#' @param batch_delay A string for the batch delay with the options: "random", "min", and "sec". Numeric examples include "1min" and "30sec". Default is "random" which is an average of 10.86 seconds (n = 1,000 simulations).
#' @param batch_size The number of rows to process in each batch. Default is 10.
#' @param case_convert A string for the case conversion of the output with the options: "upper", "lower", or NULL (no change). Default is NULL.
#' @param sanitize Extract the LLM text completion from the model's response by returning only content in \code{<result>} XML tags. Additionally, remove all punctuation. This feature prevents unwanted text (e.g., preamble) or punctuation from being included in the model's output. Default is FALSE.
#' @param attempts The maximum number of loop retry attempts. Default is 1.
#' @param log_name A string for the name of the log without the \code{.rds} file extension. Default is "batchLLM-log".
#' @param hash_algo A string for a hashing algorithm from the 'digest' package. Default is \code{crc32c}.
#' @param ... Additional arguments to pass on to the LLM API function.
#' @return
#' Returns the input data frame with an additional column containing the text completion output.
#' The function also writes the output and metadata to the log file after each batch in a nested list format.
#' @importFrom openai create_chat_completion
#' @importFrom gemini.R gemini_chat
#' @importFrom stats runif
#' @importFrom digest digest
#' @importFrom dplyr mutate left_join row_number rename_with ends_with
#' @importFrom rlang enquo as_name
#' @export
#'
#' @examples
#' \dontrun{
#' library(batchLLM)
#'
#' # Set API keys
#' Sys.setenv(OPENAI_API_KEY = "your_openai_api_key")
#' Sys.setenv(ANTHROPIC_API_KEY = "your_anthropic_api_key")
#' Sys.setenv(GEMINI_API_KEY = "your_gemini_api_key")
#'
#' # Define LLM configurations
#' llm_configs <- list(
#'   list(LLM = "openai", model = "gpt-4o-mini"),
#'   list(LLM = "anthropic", model = "claude-3-haiku-20240307"),
#'   list(LLM = "google", model = "1.5-flash")
#' )
#'
#' # Apply batchLLM function to each configuration
#' beliefs <- lapply(llm_configs, function(config) {
#'   batchLLM(
#'     df = beliefs,
#'     col = statement,
#'     prompt = "classify as a fact or misinformation in one word",
#'     LLM = config$LLM,
#'     model = config$model,
#'     batch_size = 10,
#'     batch_delay = "1min",
#'     case_convert = "lower"
#'   )
#' })[[length(llm_configs)]]
#'
#' # Print the updated data frame
#' print(beliefs)
#' }
batchLLM <- function(df,
                     df_name = NULL,
                     col,
                     prompt,
                     LLM = "openai",
                     model = "gpt-4o-mini",
                     temperature = .5,
                     max_tokens = 500,
                     batch_delay = "random",
                     batch_size = 10,
                     case_convert = NULL,
                     sanitize = FALSE,
                     attempts = 1,
                     log_name = "batchLLM-log",
                     hash_algo = "crc32c",
                     ...) {
  df_string <- if (!is.null(df_name)) df_name else deparse(substitute(df))
  col <- rlang::enquo(col)
  col_string <- rlang::as_name(col)

  save_progress <- function(df, df_string, col_string, last_batch, total_time, prompt, LLM, model, temperature, new_col, status, log_name) {
    log_file <- paste0(log_name, ".rds")
    batch_log <- if (file.exists(log_file)) {
      readRDS(log_file)
    } else {
      list(data = list())
    }
    param_id <- digest::digest(df[[col_string]], algo = hash_algo)
    df_key <- paste0(df_string, "_", param_id)
    if (is.null(batch_log$data[[df_key]])) {
      batch_log$data[[df_key]] <- list(
        output = df,
        metadata = list()
      )
    } else {
      existing_output <- batch_log$data[[df_key]]$output
      suppressMessages(
        suppressWarnings(
          batch_log$data[[df_key]]$output <- dplyr::left_join(existing_output, df, by = col_string) |>
            dplyr::select(-dplyr::ends_with(".x")) |>
            dplyr::rename_with(~ sub("\\.y$", "", .), dplyr::ends_with(".y"))
        )
      )
    }
    if (is.null(batch_log$data[[df_key]]$metadata[[new_col]])) {
      batch_log$data[[df_key]]$metadata[[new_col]] <- list(
        batches = list()
      )
    }
    batch_log$data[[df_key]]$metadata[[new_col]]$batches[[as.character(last_batch)]] <- list(
      status = status,
      timestamp = Sys.time(),
      total_time = total_time,
      prompt = prompt,
      LLM = LLM,
      model = model,
      temperature = temperature
    )
    saveRDS(batch_log, log_file)
  }

  load_progress <- function(log_name) {
    log_file <- paste0(log_name, ".rds")
    if (file.exists(log_file)) {
      return(readRDS(log_file))
    } else {
      return(list(data = list()))
    }
  }

  sanitize_output <- function(content, tag = "results") {
    if (is.null(content) || is.na(content) || !nzchar(content)) {
      return(NA_character_)
    }
    result <- sub(paste0(".*<", tag, ">(.*?)</", tag, ">.*"), "\\1", content)
    if (result == content) {
      return(NA_character_)
    }
    result <- gsub("[[:punct:]]", "", result)
    return(result)
  }

  case_convert_output <- function(content, case_convert) {
    if (!is.null(case_convert) && case_convert != "none") {
      if (case_convert == "upper") {
        content <- toupper(content)
      } else if (case_convert == "lower") {
        content <- tolower(content)
      }
    }
    return(trimws(content))
  }

  batch_mutate <- function(df, df_col, df_string, col_string, system_prompt, batch_size, batch_delay, batch_num, batch_total, LLM, model, temperature, start_row, total_rows, log_name, case_convert, sanitize, max_tokens, ...) {
    build_prompt <- function(system_prompt, content_input, sanitize) {
      if (sanitize) {
        paste0(system_prompt, "(put your response in a single level of XML tags <results></results> and continue in plain text):", as.character(content_input))
      } else {
        paste0(system_prompt, ":", as.character(content_input))
      }
    }

    mutate_row <- function(df_string, df_row, content_input, system_prompt, LLM, model, temperature, batch_delay, log_name, case_convert, sanitize, max_tokens, ...) {
      if (length(content_input) == 1 && !is.na(content_input)) {
        tryCatch(
          {
            prompt <- build_prompt(system_prompt, content_input, sanitize)
            content_output <- NULL

            if (grepl("openai", LLM)) {
              completion <- create_chat_completion(
                model = model,
                temperature = temperature,
                max_tokens = max_tokens,
                messages = list(
                  list("role" = "system", "content" = prompt),
                  list("role" = "user", "content" = as.character(content_input))
                ),
                ...
              )
              if (sanitize) {
                content_output <- sanitize_output(completion$choices$message.content)
              } else {
                content_output <- completion$choices$message.content
              }
            } else if (grepl("anthropic", LLM)) {
              completion <- claudeR(
                prompt = if (grepl("claude-2", model)) {
                  prompt
                } else if (grepl("claude-3", model)) {
                  list(list(role = "user", content = prompt))
                },
                model = model,
                temperature = temperature,
                max_tokens = max_tokens,
                ...
              )
              if (sanitize) {
                content_output <- sanitize_output(completion)
              } else {
                content_output <- completion
              }
            } else if (grepl("google", LLM)) {
              completion <- gemini.R::gemini_chat(
                prompt = prompt,
                model = model,
                temperature = temperature,
                maxOutputTokens = max_tokens,
                ...
              )
              if (sanitize) {
                content_output <- sanitize_output(completion$outputs[["text"]])
              } else {
                content_output <- completion$outputs[["text"]]
              }
            }

            if (is.null(content_output)) stop("Failed to obtain content_output.")
            if (length(content_output) > 0) {
              output_text <- case_convert_output(content_output[1], case_convert)
              return(output_text)
            } else {
              stop("\U0001F6D1 Error: completion message content returned NULL or empty")
            }
          },
          error = function(e) {
            stop(paste("\U0001F6D1 Error occurred in mutate_row:", conditionMessage(e)))
          }
        )
      } else {
        stop("\U0001F6D1 Invalid input: content_input must be a single non-NA value")
      }
    }

    df <- df |> dplyr::mutate(row_number = dplyr::row_number() + start_row - 1)
    result <- vector("character", nrow(df))

    for (i in seq_len(nrow(df))) {
      if (!is.na(df_col[i])) {
        result[i] <- tryCatch(
          {
            mutate_row(
              df_string = df_string,
              df_row = df[i, , drop = FALSE],
              content_input = df_col[i],
              system_prompt = system_prompt,
              LLM = LLM,
              model = model,
              temperature = temperature,
              batch_delay = batch_delay,
              log_name = log_name,
              case_convert = case_convert,
              sanitize = sanitize,
              max_tokens = max_tokens
            )
          },
          error = function(e) {
            stop(paste("\U0001F6D1 Error in batch_mutate:", conditionMessage(e)))
          }
        )
        message(paste("\u27A4 Processed row", df$row_number[i], "of", total_rows))
      } else {
        message(paste("\u26A0\uFE0F Skipping row", df$row_number[i], "(NA value)"))
      }
      Sys.sleep(runif(1, min = 0.1, max = 0.3))
    }

    if (batch_num < batch_total) {
      message("\u231B\uFE0F Taking a break to make the API happy")

      matches <- regmatches(batch_delay, regexec("(\\d+)(\\w+)", batch_delay))[[1]]
      delay_value <- as.numeric(matches[2])
      delay_unit <- matches[3]

      if (grepl("sec", delay_unit)) {
        delay <- delay_value / 100
      } else if (grepl("min", delay_unit)) {
        delay <- delay_value * 60 / 100
      } else if (grepl("random", batch_delay)) {
        delay <- sample(seq(0.05, 0.15, by = 0.01), 1)
      } else {
        stop("\U0001F6D1 Invalid unit of time.")
      }

      for (i in 1:100) {
        Sys.sleep(delay / 100)
        if (i %in% c(25, 50, 75, 100)) {
          message(paste0("\U0001F4A4 ", i, "% through the break"))
        }
      }

    }
    df$llm_output <- result
    return(df)
  }

  if (!is.data.frame(df) || !inherits(df, "data.frame")) {
    stop("\U0001F6D1 Input must be a valid data frame.")
  }
  if (!col_string %in% colnames(df)) {
    stop(paste("\U0001F6D1 Column", col_string, "does not exist in the input data frame."))
  }
  param_id <- digest::digest(list(LLM, model, temperature, prompt, batch_size, batch_delay, max_tokens, sanitize), algo = hash_algo)
  new_col <- paste0(col_string, "_", param_id, algo = hash_algo)
  param_id <- digest::digest(df[[col_string]], algo = hash_algo)
  new_df_key <- paste0(df_string, "_", param_id)
  batch_log <- load_progress(log_name)
  if (!is.null(batch_log$data) && !is.null(batch_log$data[[new_df_key]])) {
    progress <- batch_log$data[[new_df_key]]
    if (!is.null(progress$output) && new_col %in% colnames(progress$output)) {
      output <- progress$output
      last_batch <- if (!is.null(progress$metadata[[new_col]]$batches)) {
        max(as.numeric(names(progress$metadata[[new_col]]$batches)))
      } else {
        0
      }
      total_time <- if (last_batch > 0) {
        progress$metadata[[new_col]]$batches[[as.character(last_batch)]]$total_time
      } else {
        0
      }
      if (nrow(output) == nrow(df) && !any(is.na(output[[new_col]]))) {
        message("\u2714 All rows have already been processed for this column using the current config.")
        df[[new_col]] <- output[[new_col]]
        return(df)
      }
      if (last_batch > 0) {
        message("\U0001F6A9 Resuming from batch ", last_batch + 1)
      }
    } else {
      output <- if (is.null(progress$output)) df else progress$output
      output[[new_col]] <- NA_character_
      last_batch <- 0
      total_time <- 0
    }
  } else {
    output <- df
    output[[new_col]] <- NA_character_
    last_batch <- 0
    total_time <- 0
  }
  start_time <- Sys.time()
  batch_total <- ceiling(nrow(df) / batch_size)
  for (batch_num in (last_batch + 1):batch_total) {
    message("\U0001F6A9 Starting batch ", batch_num, " of ", batch_total)
    start_row <- (batch_num - 1) * batch_size + 1
    end_row <- min(batch_num * batch_size, nrow(df))
    rows_to_process <- which(is.na(output[start_row:end_row, new_col])) + start_row - 1
    if (length(rows_to_process) == 0) {
      message("\u26A0\uFE0F Skipping batch ", batch_num, " of ", batch_total, " as all rows are already processed.")
      last_batch <- batch_num
      next
    }
    retry_flag <- TRUE
    counter <- 1
    while (retry_flag && (counter <= attempts)) {
      tryCatch(
        {
          save_progress(
            df = output,
            df_string = df_string,
            col_string = col_string,
            last_batch = batch_num - 1,
            total_time = total_time,
            prompt = prompt,
            LLM = LLM,
            model = model,
            temperature = temperature,
            new_col = new_col,
            status = "In Progress",
            log_name = log_name
          )
          output_batch <- batch_mutate(
            df = df[rows_to_process, , drop = FALSE],
            df_col = df[[col_string]][rows_to_process],
            df_string = df_string,
            col_string = col_string,
            system_prompt = prompt,
            batch_size = length(rows_to_process),
            batch_delay = batch_delay,
            batch_num = batch_num,
            batch_total = batch_total,
            LLM = LLM,
            model = model,
            temperature = temperature,
            start_row = start_row,
            total_rows = nrow(df),
            log_name = log_name,
            case_convert = case_convert,
            sanitize = sanitize,
            max_tokens = max_tokens
          )
          output[rows_to_process, new_col] <- output_batch$llm_output
          current_time <- Sys.time()
          time_elapsed_batch <- as.numeric(difftime(current_time, start_time, units = "secs"))
          total_time <- total_time + time_elapsed_batch
          last_batch <- batch_num
          save_progress(
            df = output,
            df_string = df_string,
            col_string = col_string,
            last_batch = last_batch,
            total_time = total_time,
            prompt = prompt,
            LLM = LLM,
            model = model,
            temperature = temperature,
            new_col = new_col,
            status = "Completed",
            log_name = log_name
          )
          message("\U0001F6A9 Completed batch ", batch_num, " of ", batch_total)
          retry_flag <- FALSE
        },
        error = function(e) {
          if (counter >= attempts) {
            save_progress(
              df = output,
              df_string = df_string,
              col_string = col_string,
              last_batch = batch_num - 1,
              total_time = total_time,
              prompt = prompt,
              LLM = LLM,
              model = model,
              temperature = temperature,
              new_col = new_col,
              status = "Interrupted",
              log_name = log_name
            )
            stop(paste("\U0001F6D1 Error in batch ", batch_num, " of ", batch_total, ": ", conditionMessage(e), sep = ""))
          } else {
            message(paste("\U0001F6D1 Error occurred in batch ", batch_num, " of ", batch_total, ", trying again. Data processed up to row ", max(rows_to_process), ": ", conditionMessage(e), ". Attempt: ", counter, sep = ""))
            counter <- counter + 1
            Sys.sleep(runif(1, min = 1, max = 2))
          }
        }
      )
    }
    if (end_row == nrow(df)) {
      message("\u2714 All ", batch_total, " batches processed")
      break
    }
    start_time <- Sys.time()
  }
  return(output)
}

#' @title Get Batches
#'
#' @description Get batches of generated output in a single data frame from the \code{.rds} log file.
#'
#' @param df_name A string to match the name of a processed data frame.
#' @param log_name A string specifying the name of the log without the \code{.rds} file extension. Default is "batchLLM-log".
#' @return A data frame containing the generated output.
#' @export
#'
#' @examples
#' \dontrun{
#' library(batchLLM)
#'
#' # Assuming you have a log file with data for "beliefs_40a3012b" (see batchLLM example)
#' batches <- get_batches("beliefs_40a3012b")
#' head(batches)
#'
#' # Using a custom log file name
#' custom_batches <- get_batches("beliefs_40a3012b", log_name = "custom-log.rds")
#' head(custom_batches)
#' }
get_batches <- function(df_name = NULL, log_name = "batchLLM-log") {
  log_file <- paste0(log_name, ".rds")

  if (!file.exists(log_file)) {
    stop("\u26A0\uFE0F Log file does not exist.")
  }

  batch_log <- readRDS(log_file)

  if (is.null(df_name)) {
    stop(paste(
      "\U0001F6D1 Please define 'df_name' with a valid name:",
      paste(unique(scrape_metadata()$df), collapse = ", ")
    ))
  }

  if (!df_name %in% names(batch_log$data)) {
    stop(paste0("\U0001F6D1 No data found in ", log_name, ".rds for the specified df_name"))
  }

  output <- batch_log$data[[df_name]]$output

  return(output)
}

#' @title Scrape Metadata
#'
#' @description Scrape metadata from the \code{.rds} log file.
#'
#' @param df_name Optional. A string to match the name of a processed data frame.
#' @param log_name A string specifying the name of the log file without the extension. Default is "batchLLM-log".
#' @return A data frame containing metadata.
#' @export
#'
#' @examples
#' library(batchLLM)
#'
#' # Scrape metadata for all data frames in the default log file
#' all_metadata <- scrape_metadata()
#' head(all_metadata)
#'
#' # Scrape metadata for a specific data frame
#' specific_metadata <- scrape_metadata("beliefs_40a3012b")
#' head(specific_metadata)
#'
#' # Use a custom log file name
#' custom_metadata <- scrape_metadata(log_name = "custom-log")
#' head(custom_metadata)
scrape_metadata <- function(df_name = NULL, log_name = "batchLLM-log") {
  log_file <- paste0(log_name, ".rds")

  if (!file.exists(log_file)) {
    warning("\u26A0\uFE0F Log file does not exist.")
    return(data.frame(
      df_name = character(),
      col = character(),
      batch_number = numeric(),
      status = character(),
      timestamp = character(),
      total_time = numeric(),
      prompt = character(),
      LLM = character(),
      model = character(),
      temperature = numeric(),
      stringsAsFactors = FALSE
    ))
  }

  batch_log <- readRDS(log_file)

  scrape_df <- function(df_name, df_data) {
    if (is.null(df_data$metadata) || length(df_data$metadata) == 0) {
      return(NULL)
    }
    metadata_list <- lapply(names(df_data$metadata), function(col) {
      column_data <- df_data$metadata[[col]]
      if (is.null(column_data$batches) || length(column_data$batches) == 0) {
        return(NULL)
      }
      lapply(names(column_data$batches), function(batch_num) {
        batch <- column_data$batches[[batch_num]]
        data.frame(
          df_name = df_name,
          col = col,
          batch_number = as.numeric(batch_num),
          status = batch$status,
          timestamp = batch$timestamp,
          total_time = round(batch$total_time, 2),
          prompt = batch$prompt,
          LLM = batch$LLM,
          model = batch$model,
          temperature = batch$temperature,
          stringsAsFactors = FALSE
        )
      })
    })
    do.call(rbind, unlist(metadata_list, recursive = FALSE))
  }

  if (!is.null(df_name)) {
    if (!df_name %in% names(batch_log$data)) {
      message(paste("\u26A0\uFE0F No data found for", df_name, "in the log file."))
      return(NULL)
    }
    return(scrape_df(df_name, batch_log$data[[df_name]]))
  } else {
    metadata_list <- lapply(names(batch_log$data), function(df_name) {
      scrape_df(df_name, batch_log$data[[df_name]])
    })
    metadata_df <- do.call(rbind, metadata_list)
    return(metadata_df[!is.na(metadata_df$batch_number), ])
  }
}

#' @title Interact with Anthropic's Claude API
#'
#' @description This function provides an interface to interact with Claude AI models via Anthropic's API, allowing for flexible text generation based on user inputs.
#' This function was adapted from the [claudeR](https://github.com/yrvelez/claudeR) repository by [yrvelez](https://github.com/yrvelez) on GitHub (MIT License).
#'
#' @param api_key Your API key for authentication.
#' @param prompt A string vector for Claude-2, or a list for Claude-3 specifying the input for the model.
#' @param model The model to use for the request. Default is the latest Claude-3 model.
#' @param max_tokens A maximum number of tokens to generate before stopping.
#' @param stop_sequences Optional. A list of strings upon which to stop generating.
#' @param temperature Optional. Amount of randomness injected into the response.
#' @param top_k Optional. Only sample from the top K options for each subsequent token.
#' @param top_p Optional. Does nucleus sampling.
#' @param system_prompt Optional. An optional system role specification.
#' @return The resulting completion up to and excluding the stop sequences.
#' @importFrom httr add_headers POST content http_status
#' @importFrom jsonlite fromJSON toJSON
#' @export
#'
#' @examples
#' \dontrun{
#' library(batchLLM)
#'
#' # Set API in the env or use api_key parameter in the claudeR call
#' Sys.setenv(ANTHROPIC_API_KEY = "your_anthropic_api_key")
#'
#' # Using Claude-2
#' response <- claudeR(
#'   prompt = "What is the capital of France?",
#'   model = "claude-2.1",
#'   max_tokens = 50
#' )
#' cat(response)
#'
#' # Using Claude-3
#' response <- claudeR(
#'   prompt = list(
#'     list(role = "user", content = "What is the capital of France?")
#'   ),
#'   model = "claude-3-5-sonnet-20240620",
#'   max_tokens = 50,
#'   temperature = 0.8
#' )
#' cat(response)
#'
#' # Using a system prompt
#' response <- claudeR(
#'   prompt = list(
#'     list(role = "user", content = "Summarize the history of France in one paragraph.")
#'   ),
#'   system_prompt = "You are a concise summarization assistant.",
#'   max_tokens = 500
#' )
#' cat(response)
#' }
claudeR <- function(
    prompt,
    model = "claude-3-5-sonnet-20240620",
    max_tokens = 500,
    stop_sequences = NULL,
    temperature = .7,
    top_k = -1,
    top_p = -1,
    api_key = NULL,
    system_prompt = NULL) {
  if (grepl("claude-3", model) && !is.list(prompt)) {
    stop("\U0001F6D1 Claude-3 requires the input in a list format, e.g., list(list(role = \"user\", content = \"What is the capital of France?\"))")
  }

  if (is.null(api_key)) {
    api_key <- Sys.getenv("ANTHROPIC_API_KEY")
    if (api_key == "") {
      stop("\U0001F6D1 Please provide an API key or set it as the ANTHROPIC_API_KEY environment variable.")
    }
  }

  if (grepl("claude-2", model)) {
    url <- "https://api.anthropic.com/v1/complete"
    headers <- httr::add_headers(
      "X-API-Key" = api_key,
      "Content-Type" = "application/json",
      "anthropic-version" = "2023-06-01"
    )

    prompt <- paste0("\n\nHuman: ", prompt, "\n\nAssistant: ")

    stop_sequences <- "\n\nHuman: "

    body <- paste0('{
      "prompt": "', gsub("\n", "\\\\n", prompt), '",
      "model": "', model, '",
      "max_tokens_to_sample": ', max_tokens, ',
      "stop_sequences": ["', paste(gsub("\n", "\\\\n", stop_sequences), collapse = '", "'), '"],
      "temperature": ', temperature, ',
      "top_k": ', top_k, ',
      "top_p": ', top_p, "
    }")

    response <- httr::POST(url, headers, body = body)

    if (httr::http_status(response)$category == "Success") {
      result <- jsonlite::fromJSON(httr::content(response, "text", encoding = "UTF-8"))
      return(trimws(result$completion))
    } else {
      warning(paste("\U0001F6D1 API request failed with status", httr::http_status(response)$message))
      stop("\U0001F6D1 Error details:\n", httr::content(response, "text", encoding = "UTF-8"), "\n")
    }
  }

  url <- "https://api.anthropic.com/v1/messages"

  headers <- httr::add_headers(
    "x-api-key" = api_key,
    "anthropic-version" = "2023-06-01",
    "Content-Type" = "application/json"
  )

  message_list <- lapply(prompt, function(msg) {
    list(role = msg$role, content = msg$content)
  })

  request_body_list <- list(
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    top_k = top_k,
    top_p = top_p,
    messages = message_list
  )

  if (!is.null(system_prompt)) {
    request_body_list$system <- system_prompt
  }

  body <- jsonlite::toJSON(request_body_list, auto_unbox = TRUE)

  response <- httr::POST(url, headers, body = body)

  if (httr::http_status(response)$category == "Success") {
    result <- jsonlite::fromJSON(httr::content(response, "text", encoding = "UTF-8"))
    return(result$content$text)
  } else {
    warning(paste("\U0001F6D1 API request failed with status", httr::http_status(response)$message))
    stop("\U0001F6D1 Error details:\n", httr::content(response, "text", encoding = "UTF-8"), "\n")
  }
}
