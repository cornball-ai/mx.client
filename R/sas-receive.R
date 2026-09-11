sas_commitment <- function(public, start) {
    mx.crypto::mxc_sas_commitment(public, mx.api::mx_canonical_json(start))
}

sas_agreed <- function(content, field, wanted) {
    values <- unlist(content[[field]], use.names = FALSE)
    is.character(values) && !anyNA(values) && wanted %in% values
}

sas_info <- function(sas, mac = FALSE, peer = FALSE) {
    ours <- c(sas$user_id, sas$device_id)
    theirs <- c(sas$peer_user_id, sas$peer_device_id)
    if (mac) {
        sides <- if (peer) c(theirs, ours) else c(ours, theirs)
        return(paste0("MATRIX_KEY_VERIFICATION_MAC",
            paste0(sides, collapse = ""), sas$transaction_id))
    }
    ours <- c(ours, mx.crypto::mxc_sas_public(sas$crypto))
    theirs <- c(theirs, sas$peer_ephemeral)
    sides <- if (sas$starter) c(ours, theirs) else c(theirs, ours)
    paste(c("MATRIX_KEY_VERIFICATION_SAS", sides, sas$transaction_id), collapse = "|")
}

sas_receive_start <- function(sas, content) {
    if (identical(sas$phase, "started")) {
        # Resolve simultaneous starts using byte ordering, not the R locale.
        ids <- if (identical(sas$user_id, sas$peer_user_id)) {
            c(sas$device_id, sas$peer_device_id)
        } else c(sas$user_id, sas$peer_user_id)
        if (order(ids, method = "radix")[[1L]] == 1L) return(invisible(NULL))
        sas$outbox <- Filter(function(x) x$type != "m.key.verification.start", sas$outbox)
    } else if (!identical(sas$phase, "ready")) {
        return(mx_sas_cancel(sas, "m.unexpected_message"))
    }
    valid <- identical(content$method, "m.sas.v1") &&
        sas_agreed(content, "key_agreement_protocols", "curve25519-hkdf-sha256") &&
        sas_agreed(content, "hashes", "sha256") &&
        sas_agreed(content, "message_authentication_codes", "hkdf-hmac-sha256.v2")
    displays <- intersect(c("decimal", "emoji"),
        unlist(content$short_authentication_string, use.names = FALSE))
    if (!valid || !length(displays)) return(mx_sas_cancel(sas, "m.unknown_method"))
    sas$start <- content
    sas$starter <- FALSE
    sas$crypto <- mx.crypto::mxc_sas_new()
    sas$displays <- displays
    commitment <- sas_commitment(mx.crypto::mxc_sas_public(sas$crypto), content)
    sas$phase <- "accepted"
    sas_queue(sas, "accept", list(method = "m.sas.v1",
        key_agreement_protocol = "curve25519-hkdf-sha256", hash = "sha256",
        message_authentication_code = "hkdf-hmac-sha256.v2",
        short_authentication_string = as.list(displays), commitment = commitment))
}

sas_receive_accept <- function(sas, content) {
    if (!identical(sas$phase, "started")) {
        return(mx_sas_cancel(sas, "m.unexpected_message"))
    }
    displays <- unlist(content$short_authentication_string, use.names = FALSE)
    valid <- identical(content$method, "m.sas.v1") &&
        identical(content$key_agreement_protocol, "curve25519-hkdf-sha256") &&
        identical(content$hash, "sha256") &&
        identical(content$message_authentication_code, "hkdf-hmac-sha256.v2") &&
        is.character(displays) && length(displays) > 0L && !anyNA(displays) &&
        all(displays %in% c("decimal", "emoji")) &&
        sas_scalar(content$commitment) &&
        grepl("^[A-Za-z0-9+/]{43}$", content$commitment)
    if (!valid) return(mx_sas_cancel(sas, "m.unknown_method"))
    sas$commitment <- content$commitment
    sas$displays <- displays
    sas$phase <- "key_sent"
    sas_queue(sas, "key", list(key = mx.crypto::mxc_sas_public(sas$crypto)))
}

sas_receive_key <- function(sas, content) {
    if (!sas$phase %in% c("accepted", "key_sent")) {
        return(mx_sas_cancel(sas, "m.unexpected_message"))
    }
    if (!sas_scalar(content$key) || !grepl("^[A-Za-z0-9+/]{43}$", content$key)) {
        return(mx_sas_cancel(sas, "m.invalid_message"))
    }
    if (sas$starter && !identical(sas$commitment,
        sas_commitment(content$key, sas$start))) {
        return(mx_sas_cancel(sas, "m.mismatched_commitment"))
    }
    mx.crypto::mxc_sas_establish(sas$crypto, content$key)
    sas$peer_ephemeral <- content$key
    if (!sas$starter) {
        sas_queue(sas, "key", list(key = mx.crypto::mxc_sas_public(sas$crypto)))
    }
    sas$display_bytes <- mx.crypto::mxc_sas_bytes(sas$crypto, sas_info(sas))
    sas$phase <- "sas"
}

sas_receive_mac <- function(sas, content) {
    if (!sas$phase %in% c("sas", "confirmed")) {
        return(mx_sas_cancel(sas, "m.unexpected_message"))
    }
    tags <- content$mac
    required <- paste0("ed25519:", sas$peer_device_id)
    if (!is.list(tags) || is.null(names(tags)) || anyDuplicated(names(tags)) ||
        !all(required %in% names(tags)) || !all(names(tags) %in% names(sas$peer_keys)) ||
        !all(vapply(tags, sas_scalar, logical(1))) || !sas_scalar(content$keys)) {
        return(mx_sas_cancel(sas, "m.key_mismatch"))
    }
    ids <- sort(names(tags), method = "radix")
    info <- sas_info(sas, mac = TRUE, peer = TRUE)
    valid <- mx.crypto::mxc_sas_verify_mac(sas$crypto, paste(ids, collapse = ","),
        paste0(info, "KEY_IDS"), content$keys)
    for (id in ids) {
        valid <- valid && mx.crypto::mxc_sas_verify_mac(sas$crypto,
            sas$peer_keys[[id]], paste0(info, id), tags[[id]])
    }
    if (!valid) return(mx_sas_cancel(sas, "m.key_mismatch"))
    # A valid device-only MAC is not a proof of another user's master.
    # Keep that requirement, but distinguish omission from a corrupt MAC.
    # Our own new device needs only its device proof under our local pin.
    if (!identical(sas$user_id, sas$peer_user_id) &&
        !all(names(sas$peer_keys) %in% ids)) {
        sas$cancel_detail <- "peer_master_missing"
        return(mx_sas_cancel(sas, "m.key_mismatch"))
    }
    sas$peer_mac_valid <- TRUE
    if (sas$confirmed) sas$phase <- "verified"
}

#' Receive one standard Matrix SAS protocol event
#'
#' Ignores other senders, rooms, devices, and transaction ids. Invalid
#' messages in this transaction cancel it. Duplicate identical messages do
#' not repeat operations; conflicting repeats cancel. NULL checks timeouts.
#' Feed decrypted original event type and content, not flattened chat text.
#' No transport or persistent trust operation occurs here.
#' @param sas An in-memory SAS transaction.
#' @param event A Matrix event envelope with type, sender, content, and
#'   room_id for in-room verification, or NULL.
#' @param now Current time.
#' @return The transaction, invisibly.
#' @examples
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'     example("mx_sas_session", package = "mx.client", echo = FALSE)
#'     # Deliver queued envelopes between the two synthetic, in-memory peers.
#'     relay <- function(from, to) {
#'         for (item in mx_sas_outgoing(from)) {
#'             mx_sas_receive(to, list(type = item$type, content = item$content,
#'                 sender = mx_sas_status(from)$user_id, room_id = item$room_id))
#'             mx_sas_outgoing(from, acknowledge = item$id)
#'         }
#'     }
#'     mx_sas_accept(bob)
#'     for (i in seq_len(3)) {
#'         relay(bob, alice)
#'         relay(alice, bob)
#'     }
#'     alice_status <- mx_sas_status(alice)
#'     bob_status <- mx_sas_status(bob)
#'     stopifnot(identical(alice_status$phase, "sas"),
#'         identical(bob_status$phase, "sas"),
#'         length(alice_status$decimal) == 3L,
#'         identical(alice_status$decimal, bob_status$decimal),
#'         !alice_status$confirmed, !alice_status$local_trust_recorded)
#'     # A real exchange still requires a human comparison on trusted displays.
#' }
#' @export
mx_sas_receive <- function(sas, event = NULL, now = Sys.time()) {
    sas_check(sas)
    if (sas_expire(sas, now) || is.null(event)) return(invisible(sas))
    if (!is.list(event) || !identical(event$sender, sas$peer_user_id) ||
        !identical(event$room_id, sas$room_id) || !is.list(event$content)) {
        return(invisible(sas))
    }
    content <- event$content
    id <- if (is.null(sas$room_id)) content$transaction_id else {
        relation <- content$`m.relates_to`
        if (!is.list(relation) || !identical(relation$rel_type, "m.reference"))
            NULL else relation$event_id
    }
    if (!identical(id, sas$transaction_id) ||
        (!is.null(content$from_device) &&
            !identical(content$from_device, sas$peer_device_id))) return(invisible(sas))
    type <- event$type
    if (!sas_scalar(type) || !startsWith(type, "m.key.verification.")) {
        return(invisible(sas))
    }
    tryCatch({
        canonical <- mx.api::mx_canonical_json(content)
        previous <- sas$seen[[type]]
        if (!is.null(previous)) {
            if (!identical(previous, canonical)) mx_sas_cancel(sas, "m.unexpected_message")
            return(invisible(sas))
        }
        sas$active <- as.numeric(now)
        if (identical(type, "m.key.verification.cancel")) {
            sas$phase <- "cancelled"
            sas$cancel_code <- if (sas_scalar(content$code)) content$code else "m.invalid_message"
            sas$crypto <- NULL
            sas$outbox <- list()
        } else if (identical(type, "m.key.verification.ready")) {
            if (!identical(sas$phase, "requested") || !sas$initiator ||
                !identical(content$from_device, sas$peer_device_id) ||
                !sas_agreed(content, "methods", "m.sas.v1")) {
                mx_sas_cancel(sas, "m.unexpected_message")
            } else {
                sas$phase <- "ready"
                mx_sas_start(sas, now)
            }
        } else if (identical(type, "m.key.verification.start")) {
            if (!identical(content$from_device, sas$peer_device_id)) {
                mx_sas_cancel(sas, "m.invalid_message")
            } else sas_receive_start(sas, content)
        } else if (identical(type, "m.key.verification.accept")) {
            sas_receive_accept(sas, content)
        } else if (identical(type, "m.key.verification.key")) {
            sas_receive_key(sas, content)
        } else if (identical(type, "m.key.verification.mac")) {
            sas_receive_mac(sas, content)
        } else if (identical(type, "m.key.verification.done")) {
            if (!sas$peer_mac_valid) mx_sas_cancel(sas, "m.unexpected_message") else {
                sas$peer_done <- TRUE
                if (sas$local_trust_recorded) sas$phase <- "done"
            }
        } else mx_sas_cancel(sas, "m.unknown_method")
        sas$seen[[type]] <- canonical
    }, error = function(e) mx_sas_cancel(sas, "m.invalid_message"))
    invisible(sas)
}

#' Confirm or reject the displayed Matrix SAS
#'
#' Call only after the human compares the display through a trusted channel.
#' TRUE queues MACs for this device and its master key. Both a valid peer MAC
#' and local confirmation are required before the phase becomes verified.
#' This alone does not upload cross-signing signatures.
#' @param sas An in-memory SAS transaction displaying a SAS.
#' @param matches One explicit TRUE or FALSE, without a default.
#' @param now Current time.
#' @return The transaction, invisibly.
#' @examples
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'     example("mx_sas_receive", package = "mx.client", echo = FALSE)
#'     # Demonstrate declining the comparison. No identity trust is granted.
#'     mx_sas_confirm(alice, matches = FALSE)
#'     stopifnot(identical(mx_sas_status(alice)$cancel_code, "m.mismatched_sas"),
#'         !mx_sas_status(alice)$local_trust_recorded)
#' }
#' @export
mx_sas_confirm <- function(sas, matches, now = Sys.time()) {
    sas_check(sas)
    if (sas_expire(sas, now)) return(invisible(sas))
    if (!is.logical(matches) || length(matches) != 1L || is.na(matches)) {
        stop("mx.client: explicitly confirm TRUE or reject FALSE", call. = FALSE)
    }
    if (!identical(sas$phase, "sas")) {
        stop("mx.client: no SAS is awaiting confirmation", call. = FALSE)
    }
    if (!matches) return(mx_sas_cancel(sas, "m.mismatched_sas"))
    ids <- sort(names(sas$keys), method = "radix")
    info <- sas_info(sas, mac = TRUE)
    tags <- lapply(ids, function(id) mx.crypto::mxc_sas_mac(sas$crypto,
        sas$keys[[id]], paste0(info, id)))
    names(tags) <- ids
    sas_queue(sas, "mac", list(mac = tags,
        keys = mx.crypto::mxc_sas_mac(sas$crypto, paste(ids, collapse = ","),
            paste0(info, "KEY_IDS"))))
    sas$confirmed <- TRUE
    sas$active <- as.numeric(now)
    sas$phase <- if (sas$peer_mac_valid) "verified" else "confirmed"
    invisible(sas)
}
