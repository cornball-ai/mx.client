# User-to-user trust is a signature over an independently authenticated
# master key. A valid self-signing chain alone is not that trust decision.

mx_crypto_user_verification_context <- function(client, store_dir, user_id,
                                                 master_key) {
    mx_require_crypto()
    scalar <- function(x) is.character(x) && length(x) == 1L &&
        !is.na(x) && nzchar(x)
    if (!scalar(client$user_id) || !scalar(user_id) ||
        !startsWith(user_id, "@") || identical(user_id, client$user_id)) {
        stop("mx.client: verification requires a different Matrix user id",
             call. = FALSE)
    }
    if (!scalar(master_key) ||
        !grepl("^[A-Za-z0-9+/]{43}$", master_key)) {
        stop("mx.client: supply the full independently verified master key",
             call. = FALSE)
    }
    if (!scalar(store_dir) ||
        !file.exists(file.path(store_dir, "cross-signing.json")) ||
        !file.exists(file.path(store_dir, "pickle.key")) ||
        file.info(file.path(store_dir, "pickle.key"))$size != 32L) {
        stop("mx.client: an existing cross-signing store and pickle key are ",
             "required; no identity was created", call. = FALSE)
    }
    keys <- mx_crypto_cross_signing_load(store_dir)
    self_master <- mx.crypto::mxc_signing_key_public(keys$master)
    self_user <- mx.crypto::mxc_signing_key_public(keys$user_signing)
    query <- stats::setNames(list(list(), list()), c(client$user_id, user_id))
    response <- mx.api::mx_keys_query(mx_client_session(client), query)
    mx_crypto_report_failures(response$failures, "/keys/query", strict = TRUE)
    published_master <- mx_crypto_cross_signing_public(
        response$master_keys[[client$user_id]], client$user_id, "master")
    if (!identical(published_master, self_master)) {
        stop("mx.client: local and homeserver master keys differ; ",
             "refusing the changed identity", call. = FALSE)
    }
    user_key <- response$user_signing_keys[[client$user_id]]
    published_user <- mx_crypto_cross_signing_public(
        user_key, client$user_id, "user_signing")
    if (!identical(published_user, self_user) ||
        !mx_crypto_signature_valid(user_key, client$user_id, self_master)) {
        stop("mx.client: user-signing key does not match the local identity",
             call. = FALSE)
    }
    peer <- response$master_keys[[user_id]]
    published_peer <- mx_crypto_cross_signing_public(peer, user_id, "master")
    if (!identical(published_peer, master_key)) {
        stop("mx.client: peer master key differs from the independently ",
             "verified key; refusing the changed identity", call. = FALSE)
    }
    list(keys = keys, peer = peer, status = list(
        user_id = user_id, master_key = master_key,
        signer_user_id = client$user_id, signer_master_key = self_master,
        verified = mx_crypto_signature_valid(peer, client$user_id, self_user)))
}

#' Check a directional Matrix identity verification
#'
#' Reads the homeserver's signature on another user's master key and verifies
#' it through this user's locally pinned master and user-signing keys. Both
#' identities must match their expected keys. This does not upload signatures,
#' initialize a store, run sync, or modify encryption sessions.
#'
#' @param client Matrix client config for the account whose trust is checked.
#' @param store_dir Character. That account's existing cross-signing store.
#' @param user_id Character. The other user's full Matrix id.
#' @param master_key Character. The other user's full, unpadded base64 master
#'   public key, authenticated through a trusted independent channel. Do not
#'   obtain this pin solely from the homeserver response being checked.
#' @return A list with user_id, master_key, signer_user_id, signer_master_key,
#'   and verified. FALSE means the expected identities were found but the
#'   directional trust signature was absent or invalid. Key mismatches error.
#' @examples
#' \dontrun{
#' mx_crypto_user_trust(client, existing_store, "@peer:example.org", peer_pin)
#' }
#' @export
mx_crypto_user_trust <- function(client, store_dir, user_id, master_key) {
    mx_crypto_user_verification_context(
        client, store_dir, user_id, master_key)$status
}

#' Verify another Matrix user's independently authenticated identity
#'
#' Signs the other user's pinned master key with this account's existing
#' user-signing key. Uploads only a missing or invalid signature, then queries
#' it back and verifies it before reporting success. No private keys are sent.
#' A successful upload followed by a failed read-back may already have recorded
#' trust; rerunning with the same authenticated key is safe.
#'
#' This establishes one direction only. For mutual verification, preflight
#' both accounts with \code{mx_crypto_user_trust()}, then call this function
#' once as each account using the other account's independently checked pin.
#' The two uploads are not atomic. No SAS handshake or history-key sharing is
#' performed, and devices still need their own valid self-signing chains.
#'
#' @param client Matrix client config for the account granting trust.
#' @param store_dir Character. That account's existing cross-signing store.
#' @param user_id Character. The other user's full Matrix id.
#' @param master_key Character. The other user's full master public key,
#'   authenticated independently of the homeserver being queried.
#' @return The same status list as \code{mx_crypto_user_trust()}, with verified
#'   TRUE, invisibly. An error is raised if read-back does not confirm trust.
#' @examples
#' \dontrun{
#' mx_crypto_verify_user(client, existing_store, "@peer:example.org", peer_pin)
#' }
#' @export
mx_crypto_verify_user <- function(client, store_dir, user_id, master_key) {
    context <- mx_crypto_user_verification_context(
        client, store_dir, user_id, master_key)
    if (isTRUE(context$status$verified)) {
        return(invisible(context$status))
    }
    peer <- context$peer
    peer$signatures <- NULL
    peer$unsigned <- NULL
    key_id <- paste0("ed25519:",
                     mx.crypto::mxc_signing_key_public(context$keys$user_signing))
    signed <- mx_crypto_add_signature(
        peer, context$keys$user_signing, client$user_id, key_id)
    signatures <- stats::setNames(
        list(stats::setNames(list(signed), master_key)), user_id)
    response <- mx.api::mx_keys_signatures_upload(
        mx_client_session(client), signatures)
    if (length(response$failures)) {
        stop("mx.client: homeserver rejected the user verification signature",
             call. = FALSE)
    }
    status <- mx_crypto_user_trust(client, store_dir, user_id, master_key)
    if (!isTRUE(status$verified)) {
        stop("mx.client: uploaded trust signature was not confirmed by ",
             "read-back; rerun the check before claiming verification",
             call. = FALSE)
    }
    invisible(status)
}
