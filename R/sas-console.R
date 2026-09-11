sas_is_event <- function(event) {
    is.list(event) && is.list(event$content) && sas_scalar(event$type) &&
        (startsWith(event$type, "m.key.verification.") ||
         (identical(event$type, "m.room.message") &&
          identical(event$content$msgtype, "m.key.verification.request")))
}

sas_console_read <- function(prompt) {
    if (!interactive()) {
        stop("mx.client: verification needs an interactive human console",
            call. = FALSE)
    }
    readline(prompt)
}

#' Compare a Matrix SAS through a trusted interactive console
#'
#' Drives one transaction using the application's existing event consumer.
#' No second sync loop is created by this function. The human must explicitly
#' type yes after comparing all seven emoji or all three numbers with the peer.
#' Empty input, no, or cancellation grants no trust. Do not connect the input
#' callback to an LLM or a Matrix room.
#'
#' @param sas An in-memory transaction from mx_sas_from_request().
#' @param receive Function with no arguments returning a list of original
#'   Matrix events from the sole event consumer. It should wait briefly.
#' @param send Function accepting one outgoing envelope. It must throw on
#'   failure and use the envelope's id for idempotent retries.
#' @param complete Function accepting sas, recording and checking durable trust
#'   with mx_sas_record_trust(), outside the crypto commit window.
#' @param input Function taking a prompt. The default requires an interactive
#'   console; replacement is intended for a trusted human UI or isolated tests.
#' @return A status list, invisibly. Interrupts cancel and attempt notification.
#' @examples
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'     example("mx_sas_session", package = "mx.client", echo = FALSE)
#'     # Isolated refusal example. Real input must come from a trusted human UI.
#'     sent <- new.env(parent = emptyenv())
#'     sent$events <- list()
#'     result <- mx_sas_console(bob,
#'         receive = function() list(),
#'         send = function(event) {
#'             sent$events[[length(sent$events) + 1L]] <- event
#'         },
#'         complete = function(sas) stop("No trust should be recorded"),
#'         input = function(prompt) "no")
#'     stopifnot(identical(result$phase, "cancelled"),
#'         !result$local_trust_recorded, length(sent$events) == 1L,
#'         identical(sent$events[[1]]$type, "m.key.verification.cancel"))
#' }
#' @export
mx_sas_console <- function(sas, receive, send, complete, input = sas_console_read) {
    sas_check(sas)
    if (!all(vapply(list(receive, send, complete, input), is.function, logical(1)))) {
        stop("mx.client: console callbacks must be functions", call. = FALSE)
    }
    flush <- function() {
        for (event in mx_sas_outgoing(sas)) {
            send(event)
            mx_sas_outgoing(sas, event$id)
        }
    }
    on.exit({
        if (!sas_terminal(sas)) mx_sas_cancel(sas)
        tryCatch(flush(), error = function(e) warning(
            "mx.client: verification notification failed: ", conditionMessage(e),
            call. = FALSE))
    }, add = TRUE)
    message("Verification with ", sas$peer_user_id, " / ", sas$peer_device_id)
    if (identical(sas$phase, "requested") && !sas$initiator) {
        answer <- input("Accept this verification request? Type yes: ")
        # Process cancellations that arrived while the human was reading.
        for (event in receive()) mx_sas_receive(sas, event)
        if (identical(answer, "yes")) {
            if (!sas_terminal(sas)) mx_sas_accept(sas)
        } else mx_sas_cancel(sas)
    }
    repeat {
        mx_sas_receive(sas)
        flush()
        if (sas_terminal(sas)) break
        if (identical(sas$phase, "sas") && !sas$confirmed) {
            status <- mx_sas_status(sas)
            message("Compare using the other device or a trusted independent channel.")
            if (length(status$emoji)) {
                message(paste(status$emoji, collapse = "  "))
                message(paste(status$descriptions, collapse = " | "))
            }
            if (length(status$decimal)) message(paste(status$decimal, collapse = " - "))
            answer <- input("Do all emoji or all numbers match? Type yes: ")
            for (event in receive()) mx_sas_receive(sas, event)
            if (!sas_terminal(sas)) mx_sas_confirm(sas, identical(answer, "yes"))
            next
        }
        if (identical(sas$phase, "verified") && !sas$local_trust_recorded) {
            complete(sas)
            if (!isTRUE(sas$local_trust_recorded)) {
                stop("mx.client: completion did not record and check local trust",
                    call. = FALSE)
            }
            next
        }
        for (event in receive()) mx_sas_receive(sas, event)
    }
    status <- mx_sas_status(sas)
    if (identical(status$phase, "done")) {
        message("Local trust recorded; peer acknowledged verification completion.")
    } else {
        message("Verification cancelled: ", status$cancel_code,
            if (status$local_trust_recorded) "; local trust was already recorded" else "")
        if (identical(status$cancel_detail, "peer_master_missing")) {
            message("The peer did not authenticate its master key. Restore or ",
                "verify your own cryptographic identity in the peer app, then ",
                "start a new verification. No peer identity trust was recorded.")
        }
    }
    invisible(status)
}
