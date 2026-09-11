# Read existing identity material only. Verification must not create an account.
sas_identity <- function(client, store_dir, peer_user_id, peer_device_id) {
    required <- file.path(store_dir, c("pickle.key", "account.pickle",
        "cross-signing.json"))
    if (!all(file.exists(required)) || file.info(required[1])$size != 32L) {
        stop("mx.client: SAS requires the device's existing crypto store; ",
            "no identity was created", call. = FALSE)
    }
    signing <- mx_crypto_cross_signing_load(store_dir)
    master <- mx.crypto::mxc_signing_key_public(signing$master)
    account <- mx_crypto_account(store_dir)
    local_keys <- mx.crypto::mxc_account_identity_keys(account)
    users <- unique(c(client$user_id, peer_user_id))
    result <- mx.api::mx_keys_query(mx_client_session(client),
        stats::setNames(rep(list(list()), length(users)), users))
    mx_crypto_report_failures(result$failures, "/keys/query", strict = TRUE)
    published <- mx_crypto_cross_signing_public(
        result$master_keys[[client$user_id]], client$user_id, "master")
    if (!identical(master, published)) {
        stop("mx.client: local and homeserver master keys differ", call. = FALSE)
    }
    published_self <- result$self_signing_keys[[client$user_id]]
    local_self <- mx.crypto::mxc_signing_key_public(signing$self_signing)
    if (!identical(mx_crypto_cross_signing_public(published_self,
        client$user_id, "self_signing"), local_self) ||
        !mx_crypto_signature_valid(published_self, client$user_id, master)) {
        stop("mx.client: self-signing key does not match the local identity",
            call. = FALSE)
    }
    our_device <- result$device_keys[[client$user_id]][[client$device_id]]
    own <- mx.crypto::mxc_verify_device_keys(our_device,
        client$user_id, client$device_id)
    if (!identical(own$ed25519, local_keys$ed25519) ||
        !identical(own$curve25519, local_keys$curve25519)) {
        stop("mx.client: local and published device keys differ", call. = FALSE)
    }
    peer_master <- mx_crypto_cross_signing_public(
        result$master_keys[[peer_user_id]], peer_user_id, "master")
    peer_device <- result$device_keys[[peer_user_id]][[peer_device_id]]
    peer <- mx.crypto::mxc_verify_device_keys(peer_device,
        peer_user_id, peer_device_id)
    make_keys <- function(device, device_key, master_key) {
        sas_keys(stats::setNames(list(device_key, master_key),
            paste0("ed25519:", c(device, master_key))), device)
    }
    # Preflight the signing authority before inviting the human to compare.
    if (!identical(client$user_id, peer_user_id)) {
        mx_crypto_user_verification_context(client, store_dir,
            peer_user_id, peer_master)
    } else if (!identical(peer_master, master)) {
        stop("mx.client: another device claims a different master key", call. = FALSE)
    }
    list(keys = make_keys(client$device_id, own$ed25519, master),
        peer_keys = make_keys(peer_device_id, peer$ed25519, peer_master),
        signing = signing, peer_device = peer_device)
}

#' Create a SAS transaction from an incoming verification request
#'
#' Validates the request's age, recipient, device and method, then reads a
#' fixed key snapshot. No sync, transport, new identity, or trust upload occurs.
#' Requests are accepted only when the operator calls mx_sas_accept().
#' @param client This device's Matrix client config.
#' @param store_dir This device's existing crypto store.
#' @param event Original request envelope from the existing event consumer.
#' @param now Current time.
#' @return An in-memory SAS transaction, or NULL for an irrelevant/expired request.
#' @examples
#' # Ordinary messages are ignored without reading a store or contacting a server.
#' client <- mx_client_from_config(list(user_id = "@alice:example.org",
#'     device_id = "ALICE"))
#' event <- list(type = "m.room.message", sender = "@bob:example.org",
#'     content = list(msgtype = "m.text", body = "Hello"))
#' unused_store <- tempfile("unused-crypto-store-")
#' stopifnot(is.null(mx_sas_from_request(client, unused_store, event)),
#'     !file.exists(unused_store))
#' # See mx_verify_console() for receiving real requests using an existing store.
#' @export
mx_sas_from_request <- function(client, store_dir, event, now = Sys.time()) {
    if (length(now) != 1L || !is.finite(as.numeric(now))) {
        stop("mx.client: now must be one finite time", call. = FALSE)
    }
    if (!is.list(event) || !is.list(event$content)) return(NULL)
    c <- event$content
    room <- event$room_id
    in_room <- !is.null(room)
    request <- if (in_room) identical(event$type, "m.room.message") &&
        identical(c$msgtype, "m.key.verification.request") &&
        identical(c$to, client$user_id) else
        identical(event$type, "m.key.verification.request")
    id <- if (in_room) event$event_id else c$transaction_id
    timestamp <- if (in_room) event$origin_server_ts else c$timestamp
    valid <- request && sas_scalar(event$sender) && sas_scalar(c$from_device) &&
        sas_scalar(id) && sas_agreed(c, "methods", "m.sas.v1") &&
        is.numeric(timestamp) && length(timestamp) == 1L && is.finite(timestamp) &&
        timestamp / 1000 > as.numeric(now) - 600 &&
        timestamp / 1000 <= as.numeric(now) + 300 &&
        !(identical(event$sender, client$user_id) &&
            identical(c$from_device, client$device_id))
    if (!valid) return(NULL)
    sas_require_crypto()
    snapshot <- sas_identity(client, store_dir, event$sender, c$from_device)
    sas <- mx_sas_session(client$user_id, client$device_id, snapshot$keys,
        event$sender, c$from_device, snapshot$peer_keys, id, room, now = now)
    sas$created <- min(as.numeric(now), timestamp / 1000)
    sas
}

#' Record trust after a human-confirmed, authenticated SAS exchange
#'
#' Rechecks the fixed identity snapshot, signs the peer master with this
#' user's user-signing key (or its own peer device with its self-signing key),
#' and verifies server read-back. Only then is done queued. A peer's done
#' acknowledgement does not expose or prove its private user-signing key.
#' @param sas A SAS transaction with both human confirmation and valid peer MACs.
#' @param client This device's Matrix client config.
#' @param store_dir This device's existing cross-signing store.
#' @param now Current time.
#' @return The transaction, invisibly. Errors leave completion retryable.
#' @examples
#' if (requireNamespace("mx.crypto", quietly = TRUE)) {
#'     example("mx_sas_session", package = "mx.client", echo = FALSE)
#'     client <- mx_client_from_config(list(user_id = "@alice:example.org",
#'         device_id = "ALICE"))
#'     unused_store <- tempfile("unused-crypto-store-")
#'     # An unconfirmed exchange cannot grant trust or access the crypto store.
#'     try(mx_sas_record_trust(alice, client, unused_store))
#'     stopifnot(!mx_sas_status(alice)$local_trust_recorded,
#'         !file.exists(unused_store))
#' }
#' # mx_verify_console() calls this after human confirmation and valid peer MACs.
#' @export
mx_sas_record_trust <- function(sas, client, store_dir, now = Sys.time()) {
    sas_check(sas)
    if (!identical(client$user_id, sas$user_id) ||
        !identical(client$device_id, sas$device_id)) {
        stop("mx.client: SAS belongs to a different device", call. = FALSE)
    }
    if (isTRUE(sas$local_trust_recorded)) return(invisible(sas))
    if (sas_expire(sas, now) || !identical(sas$phase, "verified") ||
        !isTRUE(sas$confirmed) || !isTRUE(sas$peer_mac_valid)) {
        stop("mx.client: human confirmation and valid peer MACs are required",
            call. = FALSE)
    }
    current <- sas_identity(client, store_dir, sas$peer_user_id, sas$peer_device_id)
    if (!identical(current$keys, sas$keys) ||
        !identical(current$peer_keys, sas$peer_keys)) {
        mx_sas_cancel(sas, "m.key_mismatch")
        stop("mx.client: identity keys changed during SAS verification", call. = FALSE)
    }
    if (!identical(sas$user_id, sas$peer_user_id)) {
        master <- sas$peer_keys[[setdiff(names(sas$peer_keys),
            paste0("ed25519:", sas$peer_device_id))]]
        mx_crypto_verify_user(client, store_dir, sas$peer_user_id, master)
    } else {
        key <- current$signing$self_signing
        public <- mx.crypto::mxc_signing_key_public(key)
        if (!mx_crypto_signature_valid(current$peer_device, sas$user_id, public)) {
            object <- current$peer_device
            object$signatures <- object$unsigned <- NULL
            signed <- mx_crypto_add_signature(object, key, sas$user_id,
                paste0("ed25519:", public))
            response <- mx.api::mx_keys_signatures_upload(mx_client_session(client),
                stats::setNames(list(stats::setNames(list(signed),
                    sas$peer_device_id)), sas$user_id))
            mx_crypto_report_failures(response$failures, "SAS signature upload",
                strict = TRUE)
            current <- sas_identity(client, store_dir, sas$peer_user_id,
                sas$peer_device_id)
        }
        if (!mx_crypto_signature_valid(current$peer_device, sas$user_id, public)) {
            stop("mx.client: device trust signature was not confirmed by read-back",
                call. = FALSE)
        }
        if (!identical(current$keys, sas$keys) ||
            !identical(current$peer_keys, sas$peer_keys)) {
            mx_sas_cancel(sas, "m.key_mismatch")
            stop("mx.client: device keys changed during trust read-back",
                call. = FALSE)
        }
    }
    sas$local_trust_recorded <- TRUE
    sas_queue(sas, "done", list())
    if (sas$peer_done) sas$phase <- "done"
    invisible(sas)
}
