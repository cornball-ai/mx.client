# Protocol state contains ephemeral keys, never an account or ratchet writer.
# Transport and durable trust uploads are explicit operations outside it.

sas_require_crypto <- function() {
    mx_require_crypto()
    if (!"mxc_sas_commitment" %in% getNamespaceExports("mx.crypto")) {
        stop("mx.client: SAS requires mx.crypto >= 0.2.1.2 with SAS primitives",
            call. = FALSE)
    }
    invisible(NULL)
}

sas_scalar <- function(x) is.character(x) && length(x) == 1L &&
    !is.na(x) && nzchar(x) && !grepl("[[:cntrl:]]", x)

sas_keys <- function(keys, device_id) {
    if (!is.list(keys) || length(keys) != 2L || is.null(names(keys)) ||
        anyDuplicated(names(keys)) ||
        !all(vapply(keys, function(x) sas_scalar(x) &&
            grepl("^[A-Za-z0-9+/]{43}$", x), logical(1)))) {
        stop("mx.client: SAS requires a device key and a master key", call. = FALSE)
    }
    device <- paste0("ed25519:", device_id)
    other <- setdiff(names(keys), device)
    if (!device %in% names(keys) || length(other) != 1L ||
        !identical(other, paste0("ed25519:", keys[[other]]))) {
        stop("mx.client: invalid or colliding SAS key identifiers", call. = FALSE)
    }
    keys
}

sas_check <- function(sas) {
    if (!inherits(sas, "mx_sas") || !is.environment(sas)) {
        stop("mx.client: expected a SAS transaction", call. = FALSE)
    }
}

sas_wire <- function(sas, content) {
    content$from_device <- sas$device_id
    if (is.null(sas$room_id)) {
        content$transaction_id <- sas$transaction_id
    } else {
        content$`m.relates_to` <- list(rel_type = "m.reference",
            event_id = sas$transaction_id)
    }
    content
}

sas_queue <- function(sas, type, content) {
    sas$serial <- sas$serial + 1L
    id <- paste0(sas$transport_id, "-", sas$serial)
    sas$outbox[[id]] <- list(id = id, user_id = sas$peer_user_id,
        device_id = sas$peer_device_id, room_id = sas$room_id,
        type = paste0("m.key.verification.", type),
        content = sas_wire(sas, content))
    invisible(NULL)
}

sas_terminal <- function(sas) sas$phase %in% c("cancelled", "done")

sas_expire <- function(sas, now) {
    if (length(now) != 1L || !is.finite(as.numeric(now))) {
        stop("mx.client: now must be one finite time", call. = FALSE)
    }
    now <- as.numeric(now)
    idle <- if (identical(sas$phase, "requested")) 120 else 600
    if (!sas_terminal(sas) &&
        (now >= sas$created + 600 || now >= sas$active + idle)) {
        mx_sas_cancel(sas, "m.timeout")
    }
    sas_terminal(sas)
}

#' Create an in-memory Matrix SAS transaction
#'
#' Holds a fixed snapshot of both parties' device and master public keys.
#' Feed this object events from the application's existing event consumer;
#' this function does not start sync, send messages, or record trust.
#' Ephemeral state cannot be persisted. Restart interrupted transactions
#' with a new request id and new session. Only modern SAS algorithms are used.
#'
#' @param user_id This account's Matrix user id.
#' @param device_id This account's device id.
#' @param keys Named list of this device's Ed25519 key and locally trusted
#'   master key. Names are ed25519:device_id and ed25519:master_public_key.
#' @param peer_user_id The selected peer user id.
#' @param peer_device_id The selected peer device id.
#' @param peer_keys Named list containing the peer device and master public
#'   keys fetched and validated before the handshake. SAS authenticates this
#'   exact snapshot, not later replacements from a homeserver.
#' @param transaction_id Initial request event id for room verification,
#'   or the initial to-device request's transaction_id.
#' @param room_id Room id, or NULL for to-device verification.
#' @param initiator TRUE if this device sent the initial request.
#' @param now Current time. Injectable for deterministic timeout tests.
#' @return An opaque in-memory transaction. Use mx_sas_status() for display.
#' @export
mx_sas_session <- function(user_id, device_id, keys, peer_user_id,
    peer_device_id, peer_keys, transaction_id, room_id = NULL,
    initiator = FALSE, now = Sys.time()) {
    sas_require_crypto()
    fields <- list(user_id, device_id, peer_user_id, peer_device_id, transaction_id)
    if (!all(vapply(fields, sas_scalar, logical(1))) ||
        !startsWith(user_id, "@") || !startsWith(peer_user_id, "@") ||
        (!is.null(room_id) && !sas_scalar(room_id)) ||
        (identical(user_id, peer_user_id) && identical(device_id, peer_device_id)) ||
        !is.logical(initiator) || length(initiator) != 1L || is.na(initiator) ||
        length(now) != 1L || !is.finite(as.numeric(now))) {
        stop("mx.client: invalid SAS transaction identity", call. = FALSE)
    }
    sas <- new.env(parent = emptyenv())
    class(sas) <- "mx_sas"
    sas$user_id <- user_id
    sas$device_id <- device_id
    sas$keys <- sas_keys(keys, device_id)
    sas$peer_user_id <- peer_user_id
    sas$peer_device_id <- peer_device_id
    sas$peer_keys <- sas_keys(peer_keys, peer_device_id)
    sas$transaction_id <- transaction_id
    # Peer transaction ids are scoped to those devices, whereas HTTP retry
    # ids share our access-token scope. Use an independent CSPRNG nonce.
    sas$transport_id <- paste0("sas-",
        mx.crypto::mxc_sas_public(mx.crypto::mxc_sas_new()))
    sas$room_id <- room_id
    sas$initiator <- initiator
    sas$created <- sas$active <- as.numeric(now)
    sas$phase <- "requested"
    sas$outbox <- sas$seen <- list()
    sas$serial <- 0L
    sas$confirmed <- sas$peer_mac_valid <- sas$peer_done <- FALSE
    sas$local_trust_recorded <- FALSE
    sas
}

#' Accept an incoming SAS verification request
#' @param sas An in-memory SAS transaction.
#' @param now Current time.
#' @return The transaction, invisibly. A ready event is queued, not sent.
#' @export
mx_sas_accept <- function(sas, now = Sys.time()) {
    sas_check(sas)
    if (sas_expire(sas, now)) return(invisible(sas))
    if (!identical(sas$phase, "requested") || sas$initiator) {
        stop("mx.client: no incoming SAS request to accept", call. = FALSE)
    }
    sas$phase <- "ready"
    sas$active <- as.numeric(now)
    sas_queue(sas, "ready", list(methods = list("m.sas.v1")))
    invisible(sas)
}

#' Begin the SAS key agreement after request negotiation
#' @param sas An in-memory SAS transaction in the ready phase.
#' @param now Current time.
#' @return The transaction, invisibly. A start event is queued, not sent.
#' @export
mx_sas_start <- function(sas, now = Sys.time()) {
    sas_check(sas)
    if (sas_expire(sas, now)) return(invisible(sas))
    if (!identical(sas$phase, "ready")) {
        stop("mx.client: SAS request is not ready", call. = FALSE)
    }
    sas$start <- sas_wire(sas, list(method = "m.sas.v1",
        key_agreement_protocols = list("curve25519-hkdf-sha256"),
        hashes = list("sha256"),
        message_authentication_codes = list("hkdf-hmac-sha256.v2"),
        short_authentication_string = list("decimal", "emoji")))
    sas$crypto <- mx.crypto::mxc_sas_new()
    sas$starter <- TRUE
    sas$phase <- "started"
    sas$active <- as.numeric(now)
    sas_queue(sas, "start", sas$start)
    invisible(sas)
}

#' Cancel a SAS transaction without granting trust
#' @param sas An in-memory SAS transaction.
#' @param code Matrix cancellation code.
#' @return The transaction, invisibly. At most one cancellation is queued.
#' @export
mx_sas_cancel <- function(sas, code = "m.user") {
    sas_check(sas)
    if (sas_terminal(sas)) return(invisible(sas))
    if (!sas_scalar(code)) stop("mx.client: invalid cancellation code", call. = FALSE)
    sas$outbox <- list()
    sas$phase <- "cancelled"
    sas$cancel_code <- code
    sas$crypto <- NULL
    sas_queue(sas, "cancel", list(code = code, reason = code))
    invisible(sas)
}

#' Read or acknowledge queued SAS protocol messages
#'
#' Send outside any cryptographic state commit window. Acknowledge an id
#' only after transport succeeds. Retries retain the same id and payload.
#' Never display SAS codes in the Matrix conversation being verified.
#' @param sas An in-memory SAS transaction.
#' @param acknowledge Character vector of successfully sent queue ids.
#' @return A list of pending envelopes, containing type, content, destination,
#'   and a stable transport id. No private key material is included.
#' @export
mx_sas_outgoing <- function(sas, acknowledge = character()) {
    sas_check(sas)
    if (!is.character(acknowledge) || anyNA(acknowledge) ||
        !all(acknowledge %in% names(sas$outbox))) {
        stop("mx.client: unknown SAS outgoing message id", call. = FALSE)
    }
    sas$outbox[acknowledge] <- NULL
    unname(sas$outbox)
}
