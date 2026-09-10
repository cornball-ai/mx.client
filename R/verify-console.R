verification_print_messages <- function(events) {
    # Do not interleave untrusted chat text or terminal escapes with a trusted
    # verification prompt. The caller can review content in result$messages.
    message("Received ", length(events),
        " ordinary message(s); retained in result$messages for review.")
}

#' Verify a Matrix client interactively from an R console
#'
#' Owns the device's existing sync cursor and crypto store while waiting for
#' a verification request from the selected user and room. In the other
#' client, choose Start verification, then compare the emoji or numbers in
#' its UI with this trusted console. No private client database, desktop
#' keyring, or remote user's private signing key is read.
#'
#' Stop any bot or other process using this device before calling. The
#' exclusive argument is an explicit operator assertion, not a process lock.
#' Restart that process only after this call returns. Ordinary messages read
#' during this session go to on_messages and are returned for review; a bot
#' will not automatically process messages whose cursor the console advanced.
#' Existing event-loop hosts can instead use mx_sas_from_request() and
#' mx_sas_console() with their own receive/send callbacks.
#' Each attempt reloads the saved cursor and credentials, refusing a changed
#' server, user, or device identity rather than replaying the caller's old cursor.
#'
#' @param client Client loaded with mx_client_load() from its existing config.
#' @param store_dir This device's existing, initialized crypto store.
#' @param peer_user_id Full Matrix id of the person being verified.
#' @param room_id Exact room id, or NULL for to-device requests.
#' @param exclusive Must explicitly be TRUE after stopping other consumers
#'   of this device and store. FALSE refuses before any network or store access.
#' @param timeout Maximum seconds to wait for an initial request, 1 to 600.
#' @param on_messages Function receiving ordinary messages read while the
#'   console owns sync. The default reports only their count, keeping untrusted
#'   chat text out of the verification prompts; content is returned in messages.
#' @return Invisibly, a list with status, updated client, and ordinary messages.
#' @examples
#' \dontrun{
#' # First stop the service using this exact device and crypto store.
#' client <- mx_client_load(path = config_path)
#' result <- mx_verify_console(client, existing_store,
#'     "@peer:example.org", "!room:example.org", exclusive = TRUE)
#' # In the peer's Matrix app, choose Start verification.
#' # Restart the service after the console returns.
#' }
#' @export
mx_verify_console <- function(client, store_dir, peer_user_id, room_id = NULL,
    exclusive = FALSE, timeout = 120, on_messages = verification_print_messages) {
    if (!identical(exclusive, TRUE)) {
        stop("mx.client: stop other consumers of this device, then explicitly ",
            "set exclusive = TRUE; no sync or store access was started", call. = FALSE)
    }
    if (!interactive()) {
        stop("mx.client: start verification in an interactive R console", call. = FALSE)
    }
    if (!sas_scalar(peer_user_id) || !startsWith(peer_user_id, "@") ||
        (!is.null(room_id) && (!sas_scalar(room_id) || !startsWith(room_id, "!"))) ||
        !is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) ||
        timeout < 1 || timeout > 600 || !is.function(on_messages)) {
        stop("mx.client: invalid verification peer, room, timeout, or callback", call. = FALSE)
    }
    sas_require_crypto()
    ctx <- verification_context(client, store_dir)

    encrypted <- !is.null(room_id) && mx_room_encrypted(ctx$client, room_id)
    receive <- function() verification_poll(ctx, peer_user_id, on_messages)
    send <- function(event) verification_send(ctx, event, encrypted)
    complete <- function(sas) mx_sas_record_trust(sas, ctx$client, store_dir)
    message("Waiting for Start verification from ", peer_user_id,
        if (is.null(room_id)) " (to-device)" else paste0(" in ", room_id), ".")
    deadline <- Sys.time() + timeout
    sas <- NULL
    repeat {
        events <- receive()
        for (event in events) {
            if (!identical(event$sender, peer_user_id) ||
                !identical(event$room_id, room_id)) next
            if (is.null(sas)) {
                sas <- mx_sas_from_request(ctx$client, store_dir, event)
            } else mx_sas_receive(sas, event)
        }
        if (!is.null(sas) || Sys.time() >= deadline) break
    }
    status <- if (is.null(sas)) {
        message("No current verification request received before the timeout.")
        list(phase = "timeout", local_trust_recorded = FALSE)
    } else mx_sas_console(sas, receive, send, complete)
    invisible(list(status = status, client = ctx$client, messages = ctx$messages))
}
