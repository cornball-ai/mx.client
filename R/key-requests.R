# Matrix room-key request bookkeeping and transport.

mx_crypto_request_id <- function() {
    millis <- sprintf("%.0f", as.numeric(Sys.time()) * 1000)
    paste0(millis, ".", sprintf("%09d", sample.int(999999999L, 1L)))
}

mx_crypto_key_request <- function(user_id, device_id, room_id, session_id,
                                  sender_key = NULL,
                                  event_sender = NA_character_) {
    body <- list(algorithm = MX_MEGOLM, room_id = room_id,
                 session_id = session_id)
    # Deprecated since Matrix v1.3, but clients are still asked to copy it
    # when present. It is never used here to locate or trust a session.
    if (!is.null(sender_key) && nzchar(sender_key)) {
        body$sender_key <- sender_key
    }
    request_id <- mx_crypto_request_id()
    list(
        user_id = user_id,
        room_id = room_id,
        session_id = session_id,
        event_sender = event_sender,
        request_id = request_id,
        sent = FALSE,
        requesting_device_id = device_id,
        content = list(action = "request", body = body,
                       request_id = request_id, requesting_device_id = device_id)
    )
}

mx_crypto_key_request_cancellation <- function(request) {
    list(
        user_id = request$user_id,
        room_id = request$room_id,
        session_id = request$session_id,
        request_id = request$request_id,
        requesting_device_id = request$requesting_device_id,
        content = list(action = "request_cancellation",
                       request_id = request$request_id,
                       requesting_device_id = request$requesting_device_id)
    )
}

#' Mark successfully transmitted room-key requests
#'
#' Updates durable request records after transport succeeds. Requests remain
#' queued until marked, allowing a failed send to retry on a later poll even
#' after the original encrypted event has left the sync timeline.
#'
#' @param sessions An E2EE session set.
#' @param requests Request descriptors sent successfully.
#' @return The updated session set.
#' @export
mx_crypto_mark_key_requests_sent <- function(sessions, requests) {
    if (!length(requests)) return(sessions)
    ids <- vapply(requests, function(request) {
        id <- request$request_id %||% request$content$request_id
        if (!is.character(id) || length(id) != 1L || is.na(id) ||
            !nzchar(id)) {
            return(NA_character_)
        }
        id
    }, character(1))
    ids <- unique(ids[!is.na(ids)])
    for (key in names(sessions$key_requests %||% list())) {
        if (isTRUE(sessions$key_requests[[key]]$request_id %in% ids)) {
            sessions$key_requests[[key]]$sent <- TRUE
        }
    }
    sessions
}

# Return the verified device matching an authenticated Olm payload.
mx_crypto_matching_device <- function(decoded, sender_curve25519, devices) {
    for (d in devices %||% list()) {
        if (identical(d$user_id, decoded$sender) &&
            identical(d$ed25519, decoded$keys$ed25519) &&
            identical(d$curve25519, sender_curve25519)) {
            return(d)
        }
    }
    NULL
}

#' Send queued Matrix room-key requests or cancellations
#'
#' Sends each descriptor returned by [mx_crypto_process_sync()] as an
#' unencrypted \code{m.room_key_request} to every device of this user. The
#' receiving clients apply their own verified-device sharing policy.
#'
#' @param client Matrix client config.
#' @param requests A list of request/cancellation descriptors returned by
#'   [mx_crypto_process_sync()].
#' @return The endpoint responses, invisibly.
#' @examples
#' \dontrun{
#' mx_crypto_send_key_requests(client, result$key_requests)
#' }
#' @export
mx_crypto_send_key_requests <- function(client, requests) {
    if (!length(requests)) {
        return(invisible(list()))
    }
    s <- mx_client_session(client)
    responses <- lapply(requests, function(request) {
        if (is.null(request$user_id) || is.null(request$content)) {
            stop("invalid room-key request descriptor", call. = FALSE)
        }
        messages <- stats::setNames(
            list(list("*" = request$content)), request$user_id)
        mx.api::mx_send_to_device(s, "m.room_key_request", messages)
    })
    invisible(responses)
}
