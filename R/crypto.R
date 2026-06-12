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
#' @return A named list: the to-device \code{m.room.encrypted} content.
#' @examples
#' \dontrun{
#' content <- mx_crypto_room_key_payload(olm, my_curve, their_curve,
#'                                       "!room:ex", megolm_out)
#' }
#' @export
mx_crypto_room_key_payload <- function(olm_session, sender_curve25519,
                                       recipient_curve25519, room_id,
                                       megolm_out) {
    mx_require_crypto()
    info <- mx.crypto::mxc_megolm_outbound_info(megolm_out)
    room_key <- list(
                     type = "m.room_key",
                     content = list(algorithm = MX_MEGOLM, room_id = room_id,
                                    session_id = info$session_id,
                                    session_key = info$session_key)
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

#' Decrypt an inbound Olm to-device payload
#'
#' Accepts an \code{m.room.encrypted} to-device content addressed to this
#' device and returns the decrypted event. When it is an \code{m.room_key},
#' the caller builds an inbound Megolm session from
#' \code{content$session_key} with \code{mx_crypto_inbound_session()}.
#'
#' @param account An mx.crypto account handle.
#' @param my_curve25519 Character. This device's Curve25519 key.
#' @param content The to-device \code{m.room.encrypted} content.
#' @return The decrypted event (a parsed list), or NULL if not for us.
#' @examples
#' \dontrun{
#' ev <- mx_crypto_handle_to_device(acct, my_curve, td_content)
#' if (identical(ev$type, "m.room_key")) {
#'   inb <- mx_crypto_inbound_session(ev$content$session_key)
#' }
#' }
#' @export
mx_crypto_handle_to_device <- function(account, my_curve25519, content) {
    mx_require_crypto()
    msg <- content$ciphertext[[my_curve25519]]
    if (is.null(msg)) {
        return(NULL)
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
    jsonlite::fromJSON(plaintext, simplifyVector = FALSE)
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
