#' NA-pad blink events / missing data
#'
#' Deblinking (a.k.a. NA-padding) of time series data. The intended use of
#' this method is to remove blink-related artifacts surrounding periods of
#' missing data. For instance, when an individual blinks, there are usually
#' rapid decreases followed by increases in pupil size, with a chunk of data
#' missing in-between these 'spike'-looking events. The deblinking procedure
#' here will NA-pad each missing data point by your specified number of ms.
#'
#' @param eyeris An object of class `eyeris` dervived from [eyeris::load()].
#' @param extend Either a single number indicating the number of milliseconds to
#' pad forward/backward around each missing sample, or, a vector of length two
#' indicating different numbers of milliseconds pad forward/backward around each
#' missing sample, in the format `c(backward, forward)`.
#'
#' @return An `eyeris` object with a new column: `pupil_raw_{...}_deblink`.
#'
#' @examples
#' system.file("extdata", "memory.asc", package = "eyeris") |>
#'   eyeris::load_asc() |>
#'   eyeris::deblink(extend = 40) |> # 40 ms in both directions
#'   plot(seed = 0)
#'
#' system.file("extdata", "memory.asc", package = "eyeris") |>
#'   eyeris::load_asc() |>
#'   eyeris::deblink(extend = c(40, 50)) |> # 40 ms backward, 50 ms forward
#'   plot(seed = 0)
#'
#' @export
deblink <- function(eyeris, extend = 40) {
  eyeris |>
    pipeline_handler(deblink_pupil, "deblink", extend)
}

# based on https://github.com/dr-JT/pupillometry/blob/main/R/pupil_deblink.R
deblink_pupil <- function(x, prev_op, extend) {
  column <- dplyr::sym(prev_op)

  if (length(extend) == 1) { # symmetric blink padding case
    extend_backward <- extend
    extend_forward <- extend
  } else if (length(extend) == 2) { # asymmetric
    extend_backward <- extend[1]
    extend_forward <- extend[2]
  } else {
    cli::cli_abort(
      paste(
        "extend must either be a single integer (symmetric) or a vector of",
        "length 2 (asymmetric) in the format `c(backward, forward)`!"
      )
    )
  }

  data <- x |>
    dplyr::select(
      time = time_orig,
      pupil = !!column
    ) |>
    dplyr::mutate(
      blink = ifelse(is.na(pupil), 1, 0),
      blink.lag = dplyr::lag(blink),
      blink.lead = dplyr::lead(blink),
      blink.start = ifelse(blink == 1 & !is.na(blink.lag) & blink.lag == 0,
        time, as.numeric(NA)
      ),
      blink.start = zoo::na.locf(blink.start, na.rm = FALSE, fromLast = TRUE),
      blink.end = ifelse(blink == 1 & !is.na(blink.lead) & blink.lead == 0,
        time, as.numeric(NA)
      ),
      blink.end = zoo::na.locf(blink.end, na.rm = FALSE),
      blink = ifelse(!is.na(blink.start) &
                       time >= blink.start - extend_backward &
                       time <= blink.start, 1, blink),
      blink = ifelse(!is.na(blink.end) &
                       time <= blink.end + extend_forward &
                       time >= blink.end, 1, blink),
      pupil_deblink = ifelse(pupil == 0 | blink == 1, as.numeric(NA), pupil)
    ) |>
    dplyr::pull(pupil_deblink)

  return(data)
}
