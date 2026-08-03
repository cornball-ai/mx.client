# Stateful E2EE integration: session management on top of the crypto.R
# primitives. These functions turn "send this to an encrypted room" and
# "decrypt this sync" into concrete payloads and plaintext, holding the
# Olm and Megolm sessions in between. Transport (claiming one-time keys,
# sending to-device, sending the event) stays with the caller / mx.api;
# this layer is pure crypto state, so it is testable without a server.
#
# A session set is a list with four named maps:
#   olm        peer Curve25519 -> outbound Olm session (we encrypt to them)
#   olm_in     peer Curve25519 -> inbound Olm session  (they encrypt to us)
#   megolm_out room id          -> list(session, shared = peer curves)
#   megolm_in  "room|session_id" -> list(session, sender, sender_ed25519,
#                                        sender_bound)
#
# megolm_in carries the sender identity the Olm payload claimed when the
# key was shared, plus whether that claim was tied to a device whose
# device_keys verified. The claim alone is not evidence -- anyone can open
# an Olm session to us -- so only sender_bound justifies reporting a
# decrypted event as sender-verified. Stores written before this existed
# hold a bare pickle string there and are migrated on load.

#' Create an empty E2EE session set
#'
#' @return A session set: named lists \code{olm}, \code{olm_in},
#'   \code{megolm_out}, \code{megolm_in}.
#' @examples
#' s <- mx_crypto_sessions_new()
#' names(s)
#' @export
mx_crypto_sessions_new <- function() {
    list(olm = list(), olm_in = list(), megolm_out = list(), megolm_in = list())
}

#' Persist a session set to the crypto store
#'
#' Pickles every live session (encrypted at rest with the store key) into
#' \code{sessions.json}. Reload with \code{mx_crypto_sessions_load()}.
#'
#' @param sessions A session set.
#' @param store_dir Character. Crypto store directory.
#' @return The path written, invisibly.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   dir <- file.path(tempfile(), "crypto")
#'   mx_crypto_sessions_save(mx_crypto_sessions_new(), dir)
#' }
#' }
#' @export
mx_crypto_sessions_save <- function(sessions, store_dir) {
    mx_require_crypto()
    dir.create(store_dir, showWarnings = FALSE, recursive = TRUE)
    key <- mx_crypto_key(store_dir)
    blob <- list(
                 olm = lapply(sessions$olm, function(s) {
        mx.crypto::mxc_olm_session_pickle(s, key)
    }),
                 olm_in = lapply(sessions$olm_in, function(s) {
        mx.crypto::mxc_olm_session_pickle(s, key)
    }),
                 megolm_out = lapply(sessions$megolm_out, function(m) {
        list(session = mx.crypto::mxc_megolm_outbound_pickle(m$session, key),
             shared = as.list(m$shared))
    }),
                 megolm_in = lapply(sessions$megolm_in, function(e) {
        list(session = mx.crypto::mxc_megolm_inbound_pickle(e$session, key),
             sender = e$sender %||% NA_character_,
             sender_ed25519 = e$sender_ed25519 %||% NA_character_,
             sender_bound = isTRUE(e$sender_bound))
    })
    )
    path <- file.path(store_dir, "sessions.json")
    writeLines(jsonlite::toJSON(blob, auto_unbox = TRUE), path)
    Sys.chmod(path, mode = "0600")
    invisible(path)
}

#' Load a session set from the crypto store
#'
#' @param store_dir Character. Crypto store directory.
#' @return A session set (empty if nothing is stored yet).
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   s <- mx_crypto_sessions_load(file.path(tempfile(), "crypto"))
#' }
#' }
#' @export
mx_crypto_sessions_load <- function(store_dir) {
    mx_require_crypto()
    path <- file.path(store_dir, "sessions.json")
    if (!file.exists(path)) {
        return(mx_crypto_sessions_new())
    }
    key <- mx_crypto_key(store_dir)
    blob <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE),
                                     collapse = "\n"),
                               simplifyVector = FALSE)
    out <- mx_crypto_sessions_new()
    for (nm in names(blob$olm %||% list())) {
        out$olm[[nm]] <- mx.crypto::mxc_olm_session_unpickle(blob$olm[[nm]], key)
    }
    for (nm in names(blob$olm_in %||% list())) {
        out$olm_in[[nm]] <- mx.crypto::mxc_olm_session_unpickle(
            blob$olm_in[[nm]], key)
    }
    for (nm in names(blob$megolm_out %||% list())) {
        m <- blob$megolm_out[[nm]]
        out$megolm_out[[nm]] <- list(
                                     session = mx.crypto::mxc_megolm_outbound_unpickle(m$session, key),
                                     shared = unlist(m$shared, use.names = FALSE) %||% character())
    }
    for (nm in names(blob$megolm_in %||% list())) {
        e <- blob$megolm_in[[nm]]
        # Stores written before sender attestation held a bare pickle
        # string here. Read them rather than discarding them: dropping the
        # entry would cost a running client its ability to decrypt every
        # message in that session's history. Such sessions carry no
        # attested sender, so events they decrypt report
        # sender_verified = FALSE.
        if (is.character(e) || !is.list(e)) {
            out$megolm_in[[nm]] <- list(
                                        session = mx.crypto::mxc_megolm_inbound_unpickle(e, key),
                                        sender = NA_character_,
                                        sender_ed25519 = NA_character_,
                                        sender_bound = FALSE)
            next
        }
        out$megolm_in[[nm]] <- list(
                                    session = mx.crypto::mxc_megolm_inbound_unpickle(e$session, key),
                                    sender = e$sender %||% NA_character_,
                                    sender_ed25519 = e$sender_ed25519 %||% NA_character_,
                                    sender_bound = isTRUE(e$sender_bound))
    }
    out
}

#' Encrypt an event for an encrypted room's devices
#'
#' Ensures an outbound Megolm session for the room, shares its key with
#' any recipient device that has not received it yet (establishing an Olm
#' session, claiming a one-time key when needed), and encrypts the event.
#' Returns the to-device payloads and the \code{m.room.encrypted} event;
#' the caller sends them with \code{mx.api::mx_send_to_device()} and
#' \code{mx.api::mx_send()}.
#'
#' @param account An mx.crypto account handle.
#' @param sessions A session set.
#' @param room_id Character room id.
#' @param content Named list. Plaintext event content.
#' @param sender_curve25519 Character. This device's Curve25519 key.
#' @param device_id Character. This device's id.
#' @param recipients List of recipient devices, each a list with
#'   \code{user_id}, \code{device_id}, \code{curve25519}, \code{ed25519},
#'   and (only needed to open a new Olm session) \code{otk}, a claimed
#'   one-time key. Use \code{mx_crypto_known_devices()}, which returns
#'   exactly this shape for devices whose keys verified.
#' @param sender_user_id Character. This user's Matrix id. Required to
#'   build a spec-conformant Olm payload that the recipient can attribute.
#' @return List with \code{to_device} (per-device payloads), \code{event}
#'   (the \code{m.room.encrypted} content), and the updated \code{sessions}.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   acct <- mx.crypto::mxc_account_new()
#'   out <- mx_crypto_encrypt_for_devices(
#'     acct, mx_crypto_sessions_new(), "!r:ex",
#'     list(msgtype = "m.text", body = "hi"),
#'     mx.crypto::mxc_account_identity_keys(acct)$curve25519, "DEV",
#'     recipients = list(), sender_user_id = "@me:ex")
#'   names(out)
#' }
#' }
#' @export
mx_crypto_encrypt_for_devices <- function(account, sessions, room_id,
    content, sender_curve25519,
    device_id, recipients = list(),
    sender_user_id = NULL) {
    mx_require_crypto()
    if (length(recipients) && is.null(sender_user_id)) {
        stop("sender_user_id is required to share room keys; without it the ",
             "Olm payload cannot name its sender and recipients will ",
             "reject it", call. = FALSE)
    }
    sender_ed25519 <- mx.crypto::mxc_account_identity_keys(account)$ed25519
    mo <- sessions$megolm_out[[room_id]]
    if (is.null(mo)) {
        mo <- list(session = mx.crypto::mxc_megolm_outbound_new(),
                   shared = character())
    }

    to_device <- list()
    for (r in recipients) {
        peer <- r$curve25519
        if (peer %in% mo$shared) {
            next
        }
        if (is.null(r$ed25519) || !nzchar(r$ed25519)) {
            stop("recipient ", r$user_id %||% "<unknown>", "/",
                 r$device_id %||% "<unknown>", " has no ed25519 key; it must ",
                 "come from a verified device (mx_crypto_known_devices())",
                 call. = FALSE)
        }
        olm <- sessions$olm[[peer]]
        if (is.null(olm)) {
            if (is.null(r$otk)) {
                stop("no Olm session for ", peer,
                     " and no one-time key supplied to open one",
                     call. = FALSE)
            }
            olm <- mx.crypto::mxc_olm_create_outbound(
                account, peer_curve25519 = peer, peer_otk = r$otk)
            sessions$olm[[peer]] <- olm
        }
        td <- mx_crypto_room_key_payload(olm, sender_curve25519, peer,
            room_id, mo$session, sender_user_id, sender_ed25519,
            r$user_id, r$ed25519)
        to_device[[length(to_device) + 1L]] <- list(
            user_id = r$user_id, device_id = r$device_id, content = td)
        mo$shared <- c(mo$shared, peer)
    }

    event <- mx_crypto_encrypt_event(mo$session, content, room_id,
                                     sender_curve25519, device_id)
    sessions$megolm_out[[room_id]] <- mo
    list(to_device = to_device, event = event, sessions = sessions)
}

#' Process a sync response: store room keys, decrypt room events
#'
#' Handles inbound to-device \code{m.room.encrypted} (Olm) messages,
#' storing any \code{m.room_key} as an inbound Megolm session, then
#' decrypts \code{m.room.encrypted} timeline events whose session is
#' known. Returns normalized text events in the same shape as
#' \code{mx_extract_text_events()}, plus the updated session set.
#'
#' @param account An mx.crypto account handle.
#' @param sessions A session set.
#' @param sync_resp Parsed \code{/sync} response.
#' @param self_curve25519 Character. This device's Curve25519 key.
#' @param devices List of verified devices from
#'   \code{mx_crypto_known_devices()}, or NULL. Room keys arrive over Olm
#'   carrying a claimed sender, and anyone who can reach this device can
#'   send one, so the claim is only worth something once it is matched
#'   against a device whose \code{device_keys} verified. Without this
#'   list decrypted events always report \code{sender_verified = FALSE}:
#'   they still decrypt, but nothing attests to who sent them.
#' @param self_id Character or NULL. This user's Matrix id, for
#'   \code{is_self} tagging.
#' @return List with \code{events} (decrypted, normalized) and the updated
#'   \code{sessions}.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   acct <- mx.crypto::mxc_account_new()
#'   res <- mx_crypto_process_sync(acct, mx_crypto_sessions_new(),
#'     list(to_device = list(events = list()), rooms = list(join = list())),
#'     mx.crypto::mxc_account_identity_keys(acct)$curve25519)
#'   length(res$events)
#' }
#' }
#' @export
mx_crypto_process_sync <- function(account, sessions, sync_resp,
                                   self_curve25519, self_id = NULL,
                                   devices = NULL) {
    mx_require_crypto()
    self_ed25519 <- mx.crypto::mxc_account_identity_keys(account)$ed25519

    # 1. To-device: recover shared room keys.
    for (ev in sync_resp$to_device$events %||% list()) {
        if (!isTRUE(ev$type == "m.room.encrypted") ||
            !isTRUE(ev$content$algorithm == MX_OLM)) {
            next
        }
        msg <- ev$content$ciphertext[[self_curve25519]]
        if (is.null(msg)) {
            next
        }
        sender <- ev$content$sender_key
        plaintext <- if (identical(as.integer(msg$type), 0L)) {
            res <- mx.crypto::mxc_olm_create_inbound(account,
                peer_curve25519 = sender, prekey_b64 = msg$body)
            sessions$olm_in[[sender]] <- res$session
            rawToChar(res$plaintext)
        } else {
            s <- sessions$olm_in[[sender]]
            if (is.null(s)) {
                next
            }
            rawToChar(mx.crypto::mxc_olm_decrypt(s, msg$type, msg$body))
        }
        decoded <- jsonlite::fromJSON(plaintext, simplifyVector = FALSE)
        chk <- mx_crypto_check_olm_payload(decoded, self_id, self_ed25519,
            sender, devices)
        if (!chk$ok) {
            next
        }
        if (identical(decoded$type, "m.room_key")) {
            c <- decoded$content
            key <- paste(c$room_id, c$session_id, sep = "|")
            # Record who the payload claimed to be from, and separately
            # whether that claim was tied to a verified device. Keeping the
            # unbound claim is still useful -- it catches an ordinary user
            # forging a sender, since the server stamps the real one on the
            # envelope -- but only sender_bound justifies calling a
            # decrypted event's sender verified.
            sessions$megolm_in[[key]] <- list(
                session = mx.crypto::mxc_megolm_inbound_new(c$session_key),
                sender = decoded$sender,
                sender_ed25519 = decoded$keys$ed25519,
                sender_bound = chk$bound)
        }
    }

    # 2. Room timelines: decrypt what we have keys for.
    events <- list()
    joined <- sync_resp$rooms$join %||% list()
    for (rid in names(joined)) {
        for (ev in joined[[rid]]$timeline$events %||% list()) {
            if (!isTRUE(ev$type == "m.room.encrypted") ||
                !isTRUE(ev$content$algorithm == MX_MEGOLM)) {
                next
            }
            key <- paste(rid, ev$content$session_id, sep = "|")
            entry <- sessions$megolm_in[[key]]
            if (is.null(entry)) {
                next
            }
            dec <- tryCatch(mx_crypto_decrypt_event(entry$session, ev$content),
                            error = function(e) NULL)
            if (is.null(dec)) {
                next
            }
            # The session was handed to us over Olm by whoever claimed the
            # identity recorded here. A disagreement with the envelope is a
            # forgery either way, so drop it. But agreement alone proves
            # nothing against a hostile homeserver, which writes both the
            # envelope and (via an injected to-device message) the claim.
            # Only a sender tied to a verified device counts as verified.
            attested <- entry$sender
            verified <- FALSE
            if (!is.null(attested) && !is.na(attested)) {
                if (!identical(attested, ev$sender)) {
                    warning("mx.client: dropping event ",
                            ev$event_id %||% "<no id>", " in ", rid,
                            ": envelope claims sender ",
                            ev$sender %||% "<missing>",
                            " but the Megolm session was shared by ",
                            attested, call. = FALSE)
                    next
                }
                verified <- isTRUE(entry$sender_bound)
            }
            ct <- dec$content
            events[[length(events) + 1L]] <- list(
                room_id = rid,
                event_id = ev$event_id,
                sender = ev$sender,
                sender_verified = verified,
                is_self = isTRUE(ev$sender == self_id),
                body = ct$body,
                msgtype = ct$msgtype,
                mentions = ct$`m.mentions`$user_ids
            )
        }
    }

    list(events = events, sessions = sessions)
}
