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
#' Devices are returned only if their Ed25519 self-signature verifies
#' against the identity the homeserver claims for them. A device that
#' fails is dropped with a warning naming it, and the remaining devices
#' are still returned: one bad device must not make a room unusable.
#'
#' \code{/keys/query} answers 200 with a \code{failures} map when it could
#' not reach a server, and returns whatever it did manage. That is not the
#' same as a user having no devices, so it is never silent: by default it
#' warns, and with \code{strict = TRUE} it is an error. Encrypting to a
#' user whose devices could not be listed is how a message ends up
#' readable by nobody, so the send path asks for strict.
#'
#' @param client Matrix client config.
#' @param user_ids Character vector of Matrix user ids.
#' @param strict Logical. Treat a \code{failures} map as an error rather
#'   than a warning.
#' @return List of verified devices, each \code{list(user_id, device_id,
#'   curve25519, ed25519)}.
#' @examples
#' \dontrun{
#' mx_crypto_known_devices(client, "@bob:example.org")
#' }
#' @export
mx_crypto_known_devices <- function(client, user_ids, strict = FALSE) {
    mx_require_crypto()
    s <- mx_client_session(client)
    query <- stats::setNames(rep(list(list()), length(user_ids)), user_ids)
    resp <- mx.api::mx_keys_query(s, device_keys = query)
    mx_crypto_report_failures(resp$failures, "/keys/query", strict)
    mx_crypto_verify_device_map(resp$device_keys)
}

# A server we could not reach is not a user with no devices.
#
# Both /keys/query and /keys/claim answer 200 with a `failures` map and
# whatever they did manage beside it. Read only the successful half and an
# unreachable homeserver looks exactly like an empty one, which on the
# send path means encrypting to nobody and reporting success.
mx_crypto_report_failures <- function(failures, what, strict = FALSE) {
    if (!length(failures)) {
        return(invisible(FALSE))
    }
    msg <- paste0("mx.client: ", what, " could not reach ",
                  paste(names(failures), collapse = ", "),
                  "; devices there are unknown, not absent")
    if (isTRUE(strict)) {
        stop(msg, call. = FALSE)
    }
    warning(msg, call. = FALSE)
    invisible(TRUE)
}

# Verify every device in a parsed /keys/query device_keys map.
#
# Split out from the HTTP call so the verification logic is testable
# against fixture responses without a homeserver. The homeserver is not
# trusted here: without this check it can substitute its own Curve25519
# key for any device and read everything sent to that user.
#
# mxc_verify_device_keys() raises on failure rather than returning FALSE,
# and returns the keys it actually checked -- use those, not the raw map.
#
# Every (user_id, device_id) the homeserver named comes back on the
# "seen" attribute, verified or not. Without it a caller cannot tell a
# user with no devices from a user whose every device was dropped here,
# and those need different answers: the first is nobody to encrypt to,
# the second is everybody unreachable.
mx_crypto_verify_device_map <- function(device_keys_map) {
    out <- list()
    seen <- list()
    for (uid in names(device_keys_map %||% list())) {
        devs <- device_keys_map[[uid]]
        for (dev in names(devs %||% list())) {
            seen[[length(seen) + 1L]] <- c(user_id = uid, device_id = dev)
            keys <- tryCatch(
                             mx.crypto::mxc_verify_device_keys(devs[[dev]], uid, dev),
                             error = function(e) {
                warning("mx.client: skipping unverified device ", uid, "/",
                        dev, ": ", conditionMessage(e), call. = FALSE)
                NULL
            })
            if (is.null(keys)) {
                next
            }
            out[[length(out) + 1L]] <- list(user_id = uid, device_id = dev,
                curve25519 = keys$curve25519, ed25519 = keys$ed25519)
        }
    }
    attr(out, "seen") <- seen
    out
}

#' Claim a one-time key for each device
#'
#' Calls \code{/keys/claim} and attaches the claimed key to each device as
#' \code{$otk}, ready for \code{mx_crypto_encrypt_for_devices()}.
#'
#' Each claimed key's signature is checked against the device's Ed25519
#' key, which must itself have come from a verified \code{device_keys}
#' (that is, from \code{mx_crypto_known_devices()}). A key that fails is
#' dropped with a warning and its device comes back with no \code{otk}.
#'
#' \code{/keys/claim} carries the same \code{failures} map as
#' \code{/keys/query}, and it is handled the same way: warned about by
#' default, an error under \code{strict}.
#'
#' @param client Matrix client config.
#' @param devices List of devices from \code{mx_crypto_known_devices()}.
#' @param strict Logical. Treat a \code{failures} map as an error rather
#'   than a warning.
#' @return The devices with an \code{otk} field added where one was
#'   claimed and verified.
#' @examples
#' \dontrun{
#' devs <- mx_crypto_claim_otks(client, mx_crypto_known_devices(client, uid))
#' }
#' @export
mx_crypto_claim_otks <- function(client, devices, strict = FALSE) {
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
    mx_crypto_report_failures(resp$failures, "/keys/claim", strict)
    mx_crypto_verify_claimed_otks(devices, resp$one_time_keys %||% list())
}

# Attach verified one-time keys from a parsed /keys/claim response.
#
# Split from the HTTP call to keep it testable. The previous code took
# slot[[1]]$key and dropped the signatures beside it, so a homeserver
# could hand back a one-time key it had minted itself and we would open
# an Olm session to a device it controls.
#
# mxc_verify_one_time_key() deliberately will not look the signing key up
# for us, since doing so would re-trust the same response it is checking.
# That is why d$ed25519 has to come from an already-verified device.
mx_crypto_verify_claimed_otks <- function(devices, claimed) {
    lapply(devices, function(d) {
        slot <- claimed[[d$user_id]][[d$device_id]]
        if (!length(slot) || is.null(names(slot))) {
            return(d)
        }
        if (is.null(d$ed25519) || !nzchar(d$ed25519)) {
            warning("mx.client: no verified ed25519 key for ", d$user_id,
                    "/", d$device_id, "; cannot check its one-time key",
                    call. = FALSE)
            return(d)
        }
        # slot is "signed_curve25519:<id>" -> {key, signatures}; the outer
        # map key is part of what gets verified, so keep it.
        algo_kid <- names(slot)[[1]]
        otk <- tryCatch(
                        mx.crypto::mxc_verify_one_time_key(algo_kid, slot[[1]], d$ed25519,
                d$user_id, d$device_id),
                        error = function(e) {
            warning("mx.client: rejecting one-time key for ", d$user_id,
                    "/", d$device_id, ": ", conditionMessage(e),
                    call. = FALSE)
            NULL
        })
        if (!is.null(otk)) {
            d$otk <- otk
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
#'   from \code{member_ids}. An empty list is an error: an
#'   \code{m.room.encrypted} event whose room key was shared with nobody
#'   is unreadable by everyone, and returning its event id would report
#'   that as a successful send. Discovery finding nobody is allowed, since
#'   a room whose other members have no devices is a real room.
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
        # strict: a server that could not be reached leaves its users'
        # devices unknown, and an unknown device is not an absent one. Read
        # the successful half of a partial response and a federation blip
        # becomes a message nobody can read.
        found <- mx_crypto_known_devices(client, member_ids, strict = TRUE)
        # What the homeserver named, before verification dropped any of
        # it. Counting the survivors instead made a room where Bob's only
        # device is malformed look exactly like a room with no Bob in it:
        # nothing left to encrypt to either way, and only one of those is
        # a reason to go ahead.
        others_seen <- Filter(function(sd) {
            !(identical(sd[["user_id"]], client$user_id) &&
                              identical(sd[["device_id"]], client$device_id))
        }, attr(found, "seen") %||% list())
        # Skip our own device, and only our own. Device ids are scoped to a
        # user, not globally unique, so comparing device_id alone dropped
        # every other account whose device happened to share the name --
        # two bots both called BOT, and the one recipient vanishes while
        # the send still reports success.
        devs <- Filter(function(d) {
            !(identical(d$user_id, client$user_id) &&
                       identical(d$device_id, client$device_id)) &&
            !is.null(d$curve25519) && nzchar(d$curve25519)
        }, found)
        need <- Filter(function(d) is.null(sessions$olm[[d$curve25519]]), devs)
        have <- Filter(function(d) !is.null(sessions$olm[[d$curve25519]]), devs)
        claimed <- mx_crypto_claim_otks(client, need, strict = TRUE)
        # A device whose one-time key failed verification has no usable otk.
        # Drop it rather than letting encrypt_for_devices abort the send:
        # the remaining devices should still get the message.
        usable <- Filter(function(d) !is.null(d$otk), claimed)
        if (length(usable) < length(claimed)) {
            warning("mx.client: ", length(claimed) - length(usable), " of ",
                    length(claimed), " new devices in ", room_id,
                    " had no usable one-time key and were skipped",
                    call. = FALSE)
        }
        recipients <- c(usable, have)
        # Skipping some devices is the policy above. Skipping all of them
        # is not: the room key reaches nobody, the m.room.encrypted event
        # goes out anyway, and the caller is handed an event id for a
        # message every recipient will fail to decrypt.
        #
        # Measured against what the homeserver named, not against what
        # survived verification -- otherwise a room whose one other device
        # is malformed is indistinguishable from a room that has no other
        # device, and the second of those is fine to send to. A member who
        # has no devices at all is fine too: there is genuinely nobody to
        # share a key with, and the event still belongs in the room for
        # whatever device that member logs in later.
        if (length(others_seen) && !length(recipients)) {
            stop("mx.client: every other device in ", room_id,
                 " was skipped (", length(others_seen),
                 " named by the homeserver, none usable). Refusing to send ",
                 "an encrypted event whose room key would reach nobody.",
                 call. = FALSE)
        }
    } else if (!length(recipients)) {
        # An explicit empty list is the same unreadable event, arrived at
        # by a caller who did their own discovery. Nothing above runs for
        # them, so say it here rather than let it through.
        stop("mx.client: recipients is empty. Refusing to send an encrypted ",
             "event whose room key would reach nobody; pass recipients = ",
             "NULL with member_ids to have them discovered.", call. = FALSE)
    }

    out <- mx_crypto_encrypt_for_devices(account, sessions, room_id,
        content, sender_curve, client$device_id, recipients = recipients,
        sender_user_id = client$user_id)
    for (p in out$to_device) {
        messages <- stats::setNames(
                                    list(stats::setNames(list(p$content), p$device_id)), p$user_id)
        mx.api::mx_send_to_device(s, "m.room.encrypted", messages)
    }
    event_id <- mx.api::mx_send_event(s, room_id, "m.room.encrypted", out$event)
    mx_crypto_sessions_save(out$sessions, store_dir)
    list(event_id = event_id, sessions = out$sessions)
}
