# End-to-end encryption orchestration: ties mx.crypto's Olm/Megolm
# ratchets to the Matrix payload shapes and (via mx.api) the keys and
# to-device transport. mx.crypto does the cryptography; this file builds
# and consumes the m.room.encrypted / m.room_key envelopes around it.
#
# mx.crypto is a Suggests: every entry point guards with this helper, so
# the package installs and the non-encrypted paths work without a Rust
# toolchain.

MX_MEGOLM <- "m.megolm.v1.aes-sha2"
MX_OLM <- "m.olm.v1.curve25519-aes-sha2"

mx_require_crypto <- function() {
    if (!requireNamespace("mx.crypto", quietly = TRUE)) {
        stop("End-to-end encryption requires the 'mx.crypto' package. ",
             "Install it from CRAN before calling this again.", call. = FALSE)
    }
}

# ---- crypto store ----------------------------------------------------

#' Directory holding this client's encryption state
#'
#' The crypto store keeps the pickled Olm account, the 32-byte key that
#' encrypts those pickles at rest, and (later) per-peer Olm and per-room
#' Megolm sessions. It lives beside the JSON config under
#' \code{tools::R_user_dir()}.
#'
#' @param app Character. Application namespace.
#' @param path Character or NULL. Explicit store directory.
#' @return Character directory path.
#' @examples
#' mx_crypto_store_dir("myapp", path = tempfile())
#' @export
mx_crypto_store_dir <- function(app = "mx.client", path = NULL) {
    if (!is.null(path)) {
        return(path.expand(path))
    }
    file.path(tools::R_user_dir(app, "data"), "crypto")
}

# 32 random bytes for pickle encryption, persisted at rest (mode 0600).
# Created once per store; reused thereafter.
mx_crypto_key <- function(store_dir) {
    dir.create(store_dir, showWarnings = FALSE, recursive = TRUE)
    keyfile <- file.path(store_dir, "pickle.key")
    if (file.exists(keyfile)) {
        return(readBin(keyfile, "raw", n = 32L))
    }
    key <- mx_crypto_random_bytes(32L)
    writeBin(key, keyfile)
    Sys.chmod(keyfile, mode = "0600")
    key
}

mx_crypto_random_bytes <- function(n) {
    con <- tryCatch(file("/dev/urandom", "rb", raw = TRUE),
                    error = function(e) NULL)
    if (!is.null(con)) {
        on.exit(close(con))
        return(readBin(con, "raw", n = n))
    }
    # Portable fallback: mx.crypto-free hosts (e.g. Windows) get a weaker
    # source. Documented; the bots run on Linux with /dev/urandom.
    as.raw(sample.int(256L, n, replace = TRUE) - 1L)
}

#' Load or create this client's Olm account
#'
#' Unpickles \code{account.pickle} from the store, or mints a fresh
#' account and persists it. The account holds the device's long-lived
#' Curve25519/Ed25519 identity keys.
#'
#' @param store_dir Character. Crypto store directory.
#' @return An mx.crypto account handle.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   store <- mx_crypto_store_dir("myapp", path = tempfile())
#'   acct <- mx_crypto_account(store)
#'   unlink(store, recursive = TRUE)
#' }
#' }
#' @export
mx_crypto_account <- function(store_dir) {
    mx_require_crypto()
    dir.create(store_dir, showWarnings = FALSE, recursive = TRUE)
    key <- mx_crypto_key(store_dir)
    pfile <- file.path(store_dir, "account.pickle")
    if (file.exists(pfile)) {
        pickle <- paste(readLines(pfile, warn = FALSE), collapse = "")
        return(mx.crypto::mxc_account_unpickle(pickle, key))
    }
    acct <- mx.crypto::mxc_account_new()
    mx_crypto_account_save(acct, store_dir)
    acct
}

#' Persist an Olm account to the store
#'
#' @param account An mx.crypto account handle.
#' @param store_dir Character. Crypto store directory.
#' @return The pickle path, invisibly.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   store <- mx_crypto_store_dir("myapp", path = tempfile())
#'   acct <- mx_crypto_account(store)
#'   mx_crypto_account_save(acct, store)
#'   unlink(store, recursive = TRUE)
#' }
#' }
#' @export
mx_crypto_account_save <- function(account, store_dir) {
    mx_require_crypto()
    dir.create(store_dir, showWarnings = FALSE, recursive = TRUE)
    key <- mx_crypto_key(store_dir)
    pfile <- file.path(store_dir, "account.pickle")
    writeLines(mx.crypto::mxc_account_pickle(account, key), pfile)
    Sys.chmod(pfile, mode = "0600")
    invisible(pfile)
}

# ---- device keys (for /keys/upload) ----------------------------------

#' Build a signed device_keys object for upload
#'
#' Produces the \code{device_keys} structure \code{/keys/upload} expects:
#' the device's public identity keys plus an Ed25519 signature over their
#' canonical JSON. Hand the result to \code{mx.api::mx_keys_upload()}.
#'
#' @param account An mx.crypto account handle.
#' @param user_id Character. Full Matrix user id.
#' @param device_id Character. This device's id.
#' @return A named list ready to upload.
#' @examples
#' \donttest{
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'   store <- mx_crypto_store_dir("myapp", path = tempfile())
#'   acct <- mx_crypto_account(store)
#'   dk <- mx_crypto_device_keys(acct, "@bot:example.org", "DEVICEID")
#'   unlink(store, recursive = TRUE)
#' }
#' }
#' \dontrun{
#' # Uploading needs a live homeserver session:
#' mx.api::mx_keys_upload(session, device_keys = dk)
#' }
#' @export
mx_crypto_device_keys <- function(account, user_id, device_id) {
    mx_require_crypto()
    idk <- mx.crypto::mxc_account_identity_keys(account)
    body <- list(
                 user_id = user_id,
                 device_id = device_id,
                 algorithms = list(MX_OLM, MX_MEGOLM),
                 keys = stats::setNames(
                                        list(idk$curve25519, idk$ed25519),
                                        c(paste0("curve25519:", device_id), paste0("ed25519:", device_id))
        )
    )
    sig <- mx.crypto::mxc_account_sign(account, mx.api::mx_canonical_json(body))
    body$signatures <- stats::setNames(
                                       list(stats::setNames(list(sig), paste0("ed25519:", device_id))),
                                       user_id
    )
    body
}

# ---- Olm + room-key sharing (outbound) -------------------------------

#' Encrypt a Megolm room key to one device as a to-device payload
#'
#' Wraps the outbound Megolm session's key in an \code{m.room_key} event,
#' Olm-encrypts it to the recipient device, and returns the
#' \code{m.room.encrypted} to-device content to hand to
#' \code{mx.api::mx_send_to_device()}.
#'
#' @param olm_session An outbound Olm session
#'   (\code{mx.crypto::mxc_olm_create_outbound()}).
#' @param sender_curve25519 Character. This device's Curve25519 key.
#' @param recipient_curve25519 Character. Target device's Curve25519 key.
#' @param room_id Character. Room the key is for.
#' @param megolm_out An outbound Megolm session.
#' @param sender_user_id Character. This user's Matrix id.
#' @param sender_ed25519 Character. This device's Ed25519 key.
#' @param recipient_user_id Character. Target user's Matrix id.
#' @param recipient_ed25519 Character. Target device's Ed25519 key.
#' @return A named list: the to-device \code{m.room.encrypted} content.
#' @examples
#' \dontrun{
#' content <- mx_crypto_room_key_payload(olm, my_curve, their_curve,
#'                                       "!room:ex", megolm_out,
#'                                       "@me:ex", my_ed, "@them:ex", their_ed)
#' }
#' @export
mx_crypto_room_key_payload <- function(olm_session, sender_curve25519,
                                       recipient_curve25519, room_id,
                                       megolm_out, sender_user_id,
                                       sender_ed25519, recipient_user_id,
                                       recipient_ed25519) {
    mx_require_crypto()
    info <- mx.crypto::mxc_megolm_outbound_info(megolm_out)
    # The sender/recipient/keys block is not decoration: it is what lets
    # the receiving device attribute the key to us and confirm the message
    # was addressed to it. Omitting it (as this did before) leaves the
    # payload unauthenticatable and other clients reject it outright.
    room_key <- list(
                     type = "m.room_key",
                     content = list(algorithm = MX_MEGOLM, room_id = room_id,
                                    session_id = info$session_id,
                                    session_key = info$session_key),
                     sender = sender_user_id,
                     recipient = recipient_user_id,
                     recipient_keys = list(ed25519 = recipient_ed25519),
                     keys = list(ed25519 = sender_ed25519)
    )
    plaintext <- mx.api::mx_canonical_json(room_key)
    ct <- mx.crypto::mxc_olm_encrypt(olm_session, charToRaw(plaintext))
    list(
         algorithm = MX_OLM,
         sender_key = sender_curve25519,
         ciphertext = stats::setNames(
                                      list(list(type = ct$type, body = ct$body)),
                                      recipient_curve25519
        )
    )
}

# ---- inbound (receive room key + decrypt) ----------------------------

# Confirm a decrypted Olm payload was addressed to us.
#
# An Olm message decrypting successfully only proves it was encrypted to
# our Curve25519 key. It does not prove the sender meant it for us in this
# context: a homeserver can replay a payload it captured elsewhere. The
# spec's defence is the recipient block inside the plaintext, which is
# covered by the ratchet and so cannot be rewritten by the server.
#
# Returns TRUE when the payload is acceptable, FALSE (with a warning)
# otherwise. self_id may be NULL, in which case the user-id half of the
# check is skipped; callers that know their own id should always pass it.
mx_crypto_check_olm_payload <- function(decoded, self_id, self_ed25519,
                                        sender_curve25519 = NULL) {
    if (!is.null(self_id) && !identical(decoded$recipient, self_id)) {
        warning("mx.client: dropping Olm payload addressed to ",
                decoded$recipient %||% "<missing>", ", not ", self_id,
                call. = FALSE)
        return(FALSE)
    }
    if (!identical(decoded$recipient_keys$ed25519, self_ed25519)) {
        warning("mx.client: dropping Olm payload whose recipient_keys do ",
                "not match this device's Ed25519 key", call. = FALSE)
        return(FALSE)
    }
    if (is.null(decoded$sender) || is.null(decoded$keys$ed25519)) {
        warning("mx.client: dropping Olm payload with no sender identity",
                call. = FALSE)
        return(FALSE)
    }
    TRUE
}

#' Decrypt an inbound Olm to-device payload
#'
#' Accepts an \code{m.room.encrypted} to-device content addressed to this
#' device and returns the decrypted event. When it is an \code{m.room_key},
#' the caller builds an inbound Megolm session from
#' \code{content$session_key} with \code{mx_crypto_inbound_session()}.
#'
#' The decrypted payload is checked against this device's identity before
#' it is returned: a message that does not name us as recipient is
#' dropped, because decrypting successfully only proves it was encrypted
#' to our key, not that it was meant for us here.
#'
#' @param account An mx.crypto account handle.
#' @param my_curve25519 Character. This device's Curve25519 key.
#' @param content The to-device \code{m.room.encrypted} content.
#' @param self_id Character or NULL. This user's Matrix id. When NULL the
#'   recipient user-id check is skipped; pass it whenever it is known.
#' @param self_ed25519 Character or NULL. This device's Ed25519 key.
#'   Defaults to the account's own key.
#' @return The decrypted event (a parsed list), or NULL if it was not for
#'   us or failed the recipient checks.
#' @examples
#' \dontrun{
#' ev <- mx_crypto_handle_to_device(acct, my_curve, td_content,
#'                                  self_id = "@me:example.org")
#' if (identical(ev$type, "m.room_key")) {
#'   inb <- mx_crypto_inbound_session(ev$content$session_key)
#' }
#' }
#' @export
mx_crypto_handle_to_device <- function(account, my_curve25519, content,
                                       self_id = NULL, self_ed25519 = NULL) {
    mx_require_crypto()
    msg <- content$ciphertext[[my_curve25519]]
    if (is.null(msg)) {
        return(NULL)
    }
    if (is.null(self_ed25519)) {
        self_ed25519 <- mx.crypto::mxc_account_identity_keys(account)$ed25519
    }
    sender <- content$sender_key
    if (identical(as.integer(msg$type), 0L)) {
        res <- mx.crypto::mxc_olm_create_inbound(account,
            peer_curve25519 = sender, prekey_b64 = msg$body)
        plaintext <- rawToChar(res$plaintext)
    } else {
        stop("no established Olm session for a non-prekey to-device message",
             call. = FALSE)
    }
    decoded <- jsonlite::fromJSON(plaintext, simplifyVector = FALSE)
    if (!mx_crypto_check_olm_payload(decoded, self_id, self_ed25519, sender)) {
        return(NULL)
    }
    decoded
}

#' Build an inbound Megolm session from a shared room key
#'
#' @param session_key Character. The \code{session_key} from an
#'   \code{m.room_key} event.
#' @return An inbound Megolm session.
#' @examples
#' \dontrun{
#' inb <- mx_crypto_inbound_session(ev$content$session_key)
#' }
#' @export
mx_crypto_inbound_session <- function(session_key) {
    mx_require_crypto()
    mx.crypto::mxc_megolm_inbound_new(session_key)
}

# ---- event encrypt / decrypt -----------------------------------------

#' Encrypt event content for a room (Megolm)
#'
#' Returns the \code{m.room.encrypted} content to send as the event body.
#'
#' @param megolm_out An outbound Megolm session.
#' @param content Named list. The plaintext event content (e.g. an
#'   \code{m.room.message}).
#' @param room_id Character. Room id.
#' @param sender_curve25519 Character. This device's Curve25519 key.
#' @param device_id Character. This device's id.
#' @return A named list: \code{m.room.encrypted} content.
#' @examples
#' \dontrun{
#' enc <- mx_crypto_encrypt_event(megolm_out,
#'   list(msgtype = "m.text", body = "hi"), "!room:ex", my_curve, "DEV")
#' }
#' @export
mx_crypto_encrypt_event <- function(megolm_out, content, room_id,
                                    sender_curve25519, device_id) {
    mx_require_crypto()
    info <- mx.crypto::mxc_megolm_outbound_info(megolm_out)
    payload <- list(type = "m.room.message", room_id = room_id,
                    content = content)
    ct <- mx.crypto::mxc_megolm_encrypt(
                                        megolm_out, charToRaw(mx.api::mx_canonical_json(payload)))
    list(
         algorithm = MX_MEGOLM,
         sender_key = sender_curve25519,
         device_id = device_id,
         session_id = info$session_id,
         ciphertext = ct
    )
}

#' Decrypt an m.room.encrypted event (Megolm)
#'
#' @param inbound_session An inbound Megolm session for the event's
#'   \code{session_id}.
#' @param encrypted The \code{m.room.encrypted} event content.
#' @return The decrypted event payload (a parsed list).
#' @examples
#' \dontrun{
#' ev <- mx_crypto_decrypt_event(inb, encrypted_content)
#' ev$content$body
#' }
#' @export
mx_crypto_decrypt_event <- function(inbound_session, encrypted) {
    mx_require_crypto()
    res <- mx.crypto::mxc_megolm_decrypt(inbound_session, encrypted$ciphertext)
    jsonlite::fromJSON(rawToChar(res$plaintext), simplifyVector = FALSE)
}
