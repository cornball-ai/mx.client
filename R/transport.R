# E2EE transport: the network glue between the crypto state (crypto.R,
# e2ee.R) and mx.api's keys / to-device / send endpoints. These functions
# make real HTTP calls, so they are exercised by a live bring-up rather
# than the in-process loopback tests.

# Sign one published OTK for upload: {key} -> {key, signatures}.
mx_crypto_sign_otk <- function(account, key, user_id, device_id) {
    obj <- list(key = key)
    sig <- mx.crypto::mxc_account_sign(account, mx.api::mx_canonical_json(obj))
    obj$signatures <- stats::setNames(
                                      list(stats::setNames(list(sig), paste0("ed25519:", device_id))),
                                      user_id)
    obj
}

#' Publish this device's identity and one-time keys
#'
#' Builds and signs the device keys and a batch of one-time keys, uploads
#' them with \code{mx.api::mx_keys_upload()}, marks them published, and
#' persists the account. Call once after login and again to replenish
#' one-time keys.
#'
#' @param client Matrix client config (needs \code{user_id},
#'   \code{device_id}).
#' @param account An mx.crypto account handle.
#' @param store_dir Character. Crypto store directory.
#' @param n_otks Integer. Number of one-time keys to publish.
#' @return The \code{/keys/upload} response, invisibly.
#' @examples
#' \dontrun{
#' acct <- mx_crypto_account(mx_crypto_store_dir("corteza"))
#' mx_crypto_publish_keys(mx_client_load(app = "corteza"), acct,
#'                        mx_crypto_store_dir("corteza"))
#' }
#' @export
mx_crypto_publish_keys <- function(client, account, store_dir, n_otks = 50L) {
    mx_require_crypto()
    s <- mx_client_session(client)
    dk <- mx_crypto_device_keys(account, client$user_id, client$device_id)
    mx.crypto::mxc_account_generate_one_time_keys(account, as.integer(n_otks))
    otks <- mx.crypto::mxc_account_one_time_keys(account)
    signed <- stats::setNames(
                              lapply(names(otks), function(id) {
        mx_crypto_sign_otk(account, otks[[id]], client$user_id,
                           client$device_id)
    }),
                              paste0("signed_curve25519:", names(otks)))
    resp <- mx.api::mx_keys_upload(s, device_keys = dk, one_time_keys = signed)
    mx.crypto::mxc_account_mark_published(account)
    mx_crypto_account_save(account, store_dir)
    invisible(resp)
}

#' List the devices (and identity keys) of some users
#'
#' Queries \code{/keys/query} and flattens the result to a list of devices.
#'
#' @param client Matrix client config.
#' @param user_ids Character vector of Matrix user ids.
#' @return List of devices, each \code{list(user_id, device_id,
#'   curve25519, ed25519)}.
#' @examples
#' \dontrun{
#' mx_crypto_known_devices(client, "@bob:example.org")
#' }
#' @export
mx_crypto_known_devices <- function(client, user_ids) {
    mx_require_crypto()
    s <- mx_client_session(client)
    query <- stats::setNames(rep(list(list()), length(user_ids)), user_ids)
    resp <- mx.api::mx_keys_query(s, device_keys = query)
    out <- list()
    dk <- resp$device_keys %||% list()
    for (uid in names(dk)) {
        for (dev in names(dk[[uid]])) {
            keys <- dk[[uid]][[dev]]$keys
            out[[length(out) + 1L]] <- list(user_id = uid, device_id = dev,
                curve25519 = keys[[paste0("curve25519:", dev)]],
                ed25519 = keys[[paste0("ed25519:", dev)]])
        }
    }
    out
}

#' Claim a one-time key for each device
#'
#' Calls \code{/keys/claim} and attaches the claimed key to each device as
#' \code{$otk}, ready for \code{mx_crypto_encrypt_for_devices()}.
#'
#' @param client Matrix client config.
#' @param devices List of devices from \code{mx_crypto_known_devices()}.
#' @return The devices with an \code{otk} field added where one was
#'   claimed.
#' @examples
#' \dontrun{
#' devs <- mx_crypto_claim_otks(client, mx_crypto_known_devices(client, uid))
#' }
#' @export
mx_crypto_claim_otks <- function(client, devices) {
    mx_require_crypto()
    if (!length(devices)) {
        return(devices)
    }
    s <- mx_client_session(client)
    req <- list()
    for (d in devices) {
        req[[d$user_id]] <- c(req[[d$user_id]] %||% list(),
                              stats::setNames(list("signed_curve25519"), d$device_id))
    }
    resp <- mx.api::mx_keys_claim(s, one_time_keys = req)
    claimed <- resp$one_time_keys %||% list()
    lapply(devices, function(d) {
        slot <- claimed[[d$user_id]][[d$device_id]]
        if (length(slot)) {
            # slot is "signed_curve25519:<id>" -> {key, signatures}
            d$otk <- slot[[1]]$key
        }
        d
    })
}

#' Send an end-to-end encrypted message to a room
#'
#' Discovers the room members' devices (unless \code{recipients} is given),
#' claims one-time keys for any without an Olm session, shares the room key
#' over to-device, encrypts the content with Megolm, sends the
#' \code{m.room.encrypted} event, and persists the updated sessions.
#'
#' @param client Matrix client config.
#' @param account An mx.crypto account handle.
#' @param sessions A session set (see \code{mx_crypto_sessions_new()}).
#' @param room_id Character room id.
#' @param content Named list. Plaintext event content.
#' @param store_dir Character. Crypto store directory.
#' @param recipients List of recipient devices, or NULL to discover them
#'   from \code{member_ids}.
#' @param member_ids Character vector of room member user ids (used when
#'   \code{recipients} is NULL).
#' @return List with \code{event_id} and the updated \code{sessions}.
#' @examples
#' \dontrun{
#' res <- mx_send_encrypted(client, acct, sessions, "!r:ex",
#'   list(msgtype = "m.text", body = "secret"), store,
#'   member_ids = "@bob:example.org")
#' }
#' @export
mx_send_encrypted <- function(client, account, sessions, room_id, content,
                              store_dir, recipients = NULL, member_ids = NULL) {
    mx_require_crypto()
    s <- mx_client_session(client)
    sender_curve <- mx.crypto::mxc_account_identity_keys(account)$curve25519

    if (is.null(recipients)) {
        devs <- mx_crypto_known_devices(client, member_ids)
        # skip our own device; claim OTKs only where no Olm session exists
        devs <- Filter(function(d) {
            !identical(d$device_id, client$device_id) &&
            !is.null(d$curve25519) && nzchar(d$curve25519)
        }, devs)
        need <- Filter(function(d) is.null(sessions$olm[[d$curve25519]]), devs)
        have <- Filter(function(d) !is.null(sessions$olm[[d$curve25519]]), devs)
        recipients <- c(mx_crypto_claim_otks(client, need), have)
    }

    out <- mx_crypto_encrypt_for_devices(account, sessions, room_id,
        content, sender_curve, client$device_id, recipients = recipients)
    for (p in out$to_device) {
        messages <- stats::setNames(
                                    list(stats::setNames(list(p$content), p$device_id)), p$user_id)
        mx.api::mx_send_to_device(s, "m.room.encrypted", messages)
    }
    event_id <- mx.api::mx_send_event(s, room_id, "m.room.encrypted", out$event)
    mx_crypto_sessions_save(out$sessions, store_dir)
    list(event_id = event_id, sessions = out$sessions)
}
