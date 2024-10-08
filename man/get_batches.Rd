% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/batchLLM.R
\name{get_batches}
\alias{get_batches}
\title{Get Batches}
\usage{
get_batches(df_name = NULL, log_name = "batchLLM-log")
}
\arguments{
\item{df_name}{A string to match the name of a processed data frame.}

\item{log_name}{A string specifying the name of the log without the \code{.rds} file extension. Default is "batchLLM-log".}
}
\value{
A data frame containing the generated output.
}
\description{
Get batches of generated output in a single data frame from the \code{.rds} log file.
}
\examples{
\dontrun{
library(batchLLM)

# Assuming you have a log file with data for "beliefs_40a3012b" (see batchLLM example)
batches <- get_batches("beliefs_40a3012b")
head(batches)

# Using a custom log file name
custom_batches <- get_batches("beliefs_40a3012b", log_name = "custom-log.rds")
head(custom_batches)
}
}
