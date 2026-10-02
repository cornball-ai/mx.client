# Olm-encrypted to-device events of any type. Room keys use the dedicated
# path in e2ee.R; this is for everything else a device sends another
# device directly, such as the encryption keys of a MatrixRTC call.

# The Olm payload for one recipient device, with the sender and recipient
# blocks that let the receiver attribute it (see mx_crypto_room_key_payload).
mx_crypto_olm_payload <- function(olm_session, event_type, content,
                                  sender_user_id, sender_curve25519,
                                  sender_ed25519, recipient_user_id,
                                  recipient_curve25519, recipient_ed25519) {
    payload <- list(type = event_type, content = content,
                    sender = sender_user_id, recipient = recipient_user_id,
                    recipient_keys = list(ed25519 = recipient_ed25519),
                    keys = list(ed25519 = sender_ed25519))
    plaintext <- mx.api::mx_canonical_json(payload)
    ct <- mx.crypto::mxc_olm_encrypt(olm_session, charToRaw(plaintext))
    list(
         algorithm = MX_OLM,
         sender_key = sender_curve25519,
         ciphertext = stats::setNames(
                                      list(list(type = ct$type, body = ct$body)),
                                      recipient_curve25519)
    )
}

#' Encrypt a to-device event for a set of devices
#'
#' Produces one Olm-encrypted \code{m.room.encrypted} payload per
#' recipient device, opening an Olm session where none exists yet. Unlike
#' Megolm room keys, which are shared once per session, the event is
#' encrypted for every recipient on every call.
#'
#' @param account An mx.crypto account handle.
#' @param sessions A session set.
#' @param event_type The inner event type, e.g.
#'   \code{"io.element.call.encryption_keys"}.
#' @param content Named list. Plaintext event content.
#' @param recipients List of recipient devices as returned by
#'   \code{mx_crypto_known_devices()}: \code{user_id}, \code{device_id},
#'   \code{curve25519}, \code{ed25519}, and \code{otk} for a device
#'   without an Olm session yet.
#' @param sender_user_id Character. This user's Matrix id.
#' @return List with \code{to_device} (per-device payloads, each
#'   \code{list(user_id, device_id, content)}) and the updated
#'   \code{sessions}.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   acct <- mx.crypto::mxc_account_new()
#'   out <- mx_crypto_encrypt_to_device(acct, mx_crypto_sessions_new(),
#'     "org.example.ping", list(n = 1), recipients = list(),
#'     sender_user_id = "@me:ex")
#'   length(out$to_device)
#' }
#' }
#' @export
mx_crypto_encrypt_to_device <- function(account, sessions, event_type,
                                        content, recipients, sender_user_id) {
    mx_require_crypto()
    identity <- mx.crypto::mxc_account_identity_keys(account)
    to_device <- list()
    for (r in recipients) {
        peer <- r$curve25519
        if (is.null(peer) || !nzchar(peer) || is.null(r$ed25519) ||
            !nzchar(r$ed25519)) {
            stop("recipient ", r$user_id %||% "<unknown>", "/",
                 r$device_id %||% "<unknown>", " has no verified keys; ",
                 "recipients come from mx_crypto_known_devices()",
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
        to_device[[length(to_device) + 1L]] <- list(
            user_id = r$user_id, device_id = r$device_id,
            content = mx_crypto_olm_payload(olm, event_type, content,
                sender_user_id, identity$curve25519, identity$ed25519,
                r$user_id, peer, r$ed25519))
    }
    list(to_device = to_device, sessions = sessions)
}

# Devices ready to receive Olm: those with a session as they are, the
# rest with a freshly claimed one-time key. Devices whose claimed key did
# not verify are dropped with a warning.
mx_crypto_olm_recipients <- function(client, sessions, devices) {
    need <- Filter(function(d) is.null(sessions$olm[[d$curve25519]]), devices)
    have <- Filter(function(d) !is.null(sessions$olm[[d$curve25519]]), devices)
    claimed <- if (length(need)) {
        mx_crypto_claim_otks(client, need, strict = TRUE)
    } else {
        list()
    }
    usable <- Filter(function(d) !is.null(d$otk), claimed)
    if (length(usable) < length(claimed)) {
        warning("mx.client: ", length(claimed) - length(usable), " of ",
                length(claimed), " devices had no usable one-time key and ",
                "were skipped", call. = FALSE)
    }
    c(usable, have)
}

#' Send an Olm-encrypted to-device event
#'
#' Encrypts \code{content} for each device in \code{devices}, claiming
#' one-time keys where no Olm session exists, and delivers it with
#' \code{mx.api::mx_send_to_device()} in one request. This device itself
#' is never a recipient.
#'
#' @param client Matrix client config.
#' @param account An mx.crypto account handle.
#' @param sessions A session set.
#' @param event_type The inner event type.
#' @param content Named list. Plaintext event content.
#' @param devices List of target devices from
#'   \code{mx_crypto_known_devices()}, already narrowed to the devices
#'   that should receive the event.
#' @param store_dir Character or NULL. Where to persist the updated
#'   sessions; NULL leaves saving to the caller.
#' @return List with \code{sessions} (updated) and \code{sent}, the
#'   \code{list(user_id, device_id)} pairs the event went to.
#' @examples
#' \dontrun{
#' devs <- mx_crypto_known_devices(client, "@bob:example.org")
#' mx_send_to_device_encrypted(client, acct, sessions, "org.example.ping",
#'                             list(n = 1), devs, store_dir)
#' }
#' @export
mx_send_to_device_encrypted <- function(client, account, sessions,
                                        event_type, content, devices,
                                        store_dir = NULL) {
    mx_require_crypto()
    devices <- Filter(function(d) {
        !(identical(d$user_id, client$user_id) &&
                      identical(d$device_id, client$device_id))
    }, devices)
    recipients <- mx_crypto_olm_recipients(client, sessions, devices)
    out <- mx_crypto_encrypt_to_device(account, sessions, event_type,
                                       content, recipients, client$user_id)
    if (length(out$to_device)) {
        messages <- list()
        for (p in out$to_device) {
            messages[[p$user_id]][[p$device_id]] <- p$content
        }
        mx.api::mx_send_to_device(mx_client_session(client), "m.room.encrypted",
                                  messages)
    }
    if (!is.null(store_dir)) {
        mx_crypto_sessions_save(out$sessions, store_dir)
    }
    list(sessions = out$sessions,
         sent = lapply(out$to_device, function(p) {
        list(user_id = p$user_id, device_id = p$device_id)
    }))
}
