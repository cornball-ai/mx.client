# Matrix cross-signing for long-lived bot devices.
#
# The three private signing keys stay in the existing crypto store and use
# the same encrypted vodozemac pickle plus mode-0600 file discipline as the
# Olm account. The server only receives the public CrossSigningKey objects.

mx_crypto_cross_signing_path <- function(store_dir) {
    file.path(store_dir, "cross-signing.json")
}

mx_crypto_cross_signing_new <- function() {
    mx_require_crypto()
    list(master = mx.crypto::mxc_signing_key_new(),
         self_signing = mx.crypto::mxc_signing_key_new(),
         user_signing = mx.crypto::mxc_signing_key_new())
}

mx_crypto_cross_signing_save <- function(keys, store_dir) {
    mx_require_crypto()
    dir.create(store_dir, showWarnings = FALSE, recursive = TRUE)
    pickle_key <- mx_crypto_key(store_dir)
    blob <- list(
        version = 1L,
        master = mx.crypto::mxc_signing_key_pickle(keys$master, pickle_key),
        self_signing = mx.crypto::mxc_signing_key_pickle(
            keys$self_signing, pickle_key),
        user_signing = mx.crypto::mxc_signing_key_pickle(
            keys$user_signing, pickle_key)
    )
    path <- mx_crypto_cross_signing_path(store_dir)
    writeLines(jsonlite::toJSON(blob, auto_unbox = TRUE), path)
    Sys.chmod(path, mode = "0600")
    invisible(path)
}

#' Load locally persisted Matrix cross-signing keys
#'
#' Returns NULL when this crypto store has never bootstrapped a cross-signing
#' identity. A present but malformed store is an error: generating over it
#' would silently reset the user's Matrix identity.
#'
#' @param store_dir Character. Crypto store directory.
#' @return A list containing master, self-signing and user-signing key handles,
#'   or NULL.
#' @export
mx_crypto_cross_signing_load <- function(store_dir) {
    mx_require_crypto()
    path <- mx_crypto_cross_signing_path(store_dir)
    if (!file.exists(path)) {
        return(NULL)
    }
    blob <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE),
                                     collapse = "\n"),
                               simplifyVector = FALSE)
    crypto_store_version(blob, path)
    needed <- c("master", "self_signing", "user_signing")
    if (any(vapply(needed, function(nm) is.null(blob[[nm]]), logical(1)))) {
        stop("mx.client: invalid cross-signing store at ", path,
             "; refusing to replace an identity whose private keys may be lost",
             call. = FALSE)
    }
    pickle_key <- mx_crypto_key(store_dir)
    list(master = mx.crypto::mxc_signing_key_unpickle(blob$master, pickle_key),
         self_signing = mx.crypto::mxc_signing_key_unpickle(
             blob$self_signing, pickle_key),
         user_signing = mx.crypto::mxc_signing_key_unpickle(
             blob$user_signing, pickle_key))
}

mx_crypto_signable_json <- function(object) {
    object$signatures <- NULL
    object$unsigned <- NULL
    mx.api::mx_canonical_json(object)
}

mx_crypto_add_signature <- function(object, signer, user_id, key_id) {
    sig <- mx.crypto::mxc_signing_key_sign(
        signer, mx_crypto_signable_json(object))
    own <- object$signatures[[user_id]] %||% list()
    own[[key_id]] <- sig
    object$signatures[[user_id]] <- own
    object
}

mx_crypto_cross_signing_key <- function(key, user_id, usage) {
    public <- mx.crypto::mxc_signing_key_public(key)
    list(user_id = user_id, usage = list(usage),
         keys = stats::setNames(list(public), paste0("ed25519:", public)))
}

mx_crypto_cross_signing_objects <- function(keys, user_id, device_account,
                                             device_id) {
    master_public <- mx.crypto::mxc_signing_key_public(keys$master)
    master <- mx_crypto_cross_signing_key(keys$master, user_id, "master")
    device_sig <- mx.crypto::mxc_account_sign(
        device_account, mx_crypto_signable_json(master))
    master$signatures <- stats::setNames(
        list(stats::setNames(list(device_sig), paste0("ed25519:", device_id))),
        user_id)

    self <- mx_crypto_cross_signing_key(
        keys$self_signing, user_id, "self_signing")
    self <- mx_crypto_add_signature(
        self, keys$master, user_id, paste0("ed25519:", master_public))
    user <- mx_crypto_cross_signing_key(
        keys$user_signing, user_id, "user_signing")
    user <- mx_crypto_add_signature(
        user, keys$master, user_id, paste0("ed25519:", master_public))
    list(master = master, self_signing = self, user_signing = user)
}

mx_crypto_cross_signing_public <- function(object, user_id, usage) {
    if (!is.list(object) || !identical(object$user_id, user_id) ||
        !usage %in% unlist(object$usage, use.names = FALSE) ||
        length(object$keys) != 1L) {
        stop("mx.client: invalid ", usage, " cross-signing key for ", user_id,
             call. = FALSE)
    }
    key_id <- names(object$keys)[[1L]]
    public <- as.character(object$keys[[1L]])
    if (!identical(key_id, paste0("ed25519:", public))) {
        stop("mx.client: ", usage,
             " cross-signing key id does not match its public key",
             call. = FALSE)
    }
    public
}

mx_crypto_signature_valid <- function(object, user_id, public,
                                      key_id = paste0("ed25519:", public)) {
    tryCatch({
        sig <- object$signatures[[user_id]][[key_id]]
        !is.null(sig) && isTRUE(mx.crypto::mxc_ed25519_verify(
            public, charToRaw(mx_crypto_signable_json(object)), sig))
    }, error = function(e) FALSE)
}

# Verify that the server's master -> self-signing -> device chain is
# internally sound. Trusting the master remains a separate user decision.
mx_crypto_cross_signed_devices <- function(device_keys_map, master_keys,
                                            self_signing_keys) {
    out <- list()
    for (uid in names(device_keys_map %||% list())) {
        master <- master_keys[[uid]]
        self <- self_signing_keys[[uid]]
        if (is.null(master) || is.null(self)) {
            next
        }
        chain <- tryCatch({
            master_public <- mx_crypto_cross_signing_public(
                master, uid, "master")
            self_public <- mx_crypto_cross_signing_public(
                self, uid, "self_signing")
            if (!mx_crypto_signature_valid(self, uid, master_public)) {
                stop("self-signing key is not signed by the master key")
            }
            list(master = master_public, self = self_public)
        }, error = function(e) {
            warning("mx.client: invalid cross-signing chain for ", uid,
                    ": ", conditionMessage(e), call. = FALSE)
            NULL
        })
        if (is.null(chain)) {
            next
        }
        for (device_id in names(device_keys_map[[uid]] %||% list())) {
            device <- device_keys_map[[uid]][[device_id]]
            if (mx_crypto_signature_valid(device, uid, chain$self)) {
                out[[paste(uid, device_id, sep = "|")]] <- chain$master
            }
        }
    }
    out
}

mx_crypto_upload_cross_signing <- function(client, objects, password = NULL,
                                            auth = NULL) {
    session <- mx_client_session(client)
    upload <- function(completed_auth = NULL) {
        mx.api::mx_keys_device_signing_upload(
            session, master_key = objects$master,
            self_signing_key = objects$self_signing,
            user_signing_key = objects$user_signing,
            auth = completed_auth)
    }
    if (!is.null(auth)) {
        return(upload(auth))
    }
    tryCatch(upload(), mx_error = function(e) {
        if (!identical(e$status, 401L) || is.null(password)) {
            stop(e)
        }
        uia_session <- e$body$session
        if (is.null(uia_session)) {
            stop("mx.client: cross-signing upload requested UIA but returned ",
                 "no UIA session id", call. = FALSE)
        }
        completed <- list(
            type = "m.login.password",
            identifier = list(type = "m.id.user", user = client$user_id),
            password = password, session = uia_session)
        upload(completed)
    })
}

#' Bootstrap and sign this Matrix device's cross-signing identity
#'
#' Creates master, self-signing and user-signing keys only when neither the
#' local crypto store nor homeserver already has an identity. Existing local
#' keys are reused; a server/local mismatch aborts instead of resetting the
#' identity. The current device signs the master key and the self-signing key
#' signs the current device.
#' Valid signatures already returned by the homeserver are not re-uploaded.
#'
#' @param client Matrix client config.
#' @param device_account This device's persisted Olm account.
#' @param store_dir Character. Crypto store directory.
#' @param password Character or NULL. Account password used only for UIA.
#' @param auth Completed Matrix UIA object or NULL.
#' @return Public master, self-signing and user-signing key ids, invisibly.
#' @export
mx_crypto_cross_signing_bootstrap <- function(client, device_account,
                                               store_dir, password = NULL,
                                               auth = NULL) {
    mx_require_crypto()
    if (is.null(client$user_id) || is.null(client$device_id)) {
        stop("mx.client: cross-signing requires user_id and device_id",
             call. = FALSE)
    }
    query <- stats::setNames(list(list()), client$user_id)
    current <- mx.api::mx_keys_query(mx_client_session(client), query)
    server_master <- current$master_keys[[client$user_id]]
    keys <- mx_crypto_cross_signing_load(store_dir)

    if (is.null(keys)) {
        if (!is.null(server_master)) {
            stop("mx.client: the homeserver already has a cross-signing ",
                 "identity for ", client$user_id, " but this crypto store ",
                 "does not hold its private keys; refusing an implicit reset",
                 call. = FALSE)
        }
        keys <- mx_crypto_cross_signing_new()
        mx_crypto_cross_signing_save(keys, store_dir)
    }

    objects <- mx_crypto_cross_signing_objects(
        keys, client$user_id, device_account, client$device_id)
    local_master <- mx_crypto_cross_signing_public(
        objects$master, client$user_id, "master")
    if (!is.null(server_master)) {
        published <- mx_crypto_cross_signing_public(
            server_master, client$user_id, "master")
        if (!identical(local_master, published)) {
            stop("mx.client: local and homeserver cross-signing master keys ",
                 "differ; refusing an implicit identity reset", call. = FALSE)
        }
    } else {
        mx_crypto_upload_cross_signing(client, objects, password, auth)
    }

    raw_device <- current$device_keys[[client$user_id]][[client$device_id]]
    if (is.null(raw_device)) {
        stop("mx.client: homeserver did not return this device's published keys",
             call. = FALSE)
    }
    verified <- mx.crypto::mxc_verify_device_keys(
        raw_device, client$user_id, client$device_id)
    actual_ed <- mx.crypto::mxc_account_identity_keys(device_account)$ed25519
    if (!identical(verified$ed25519, actual_ed)) {
        stop("mx.client: published device Ed25519 key does not match this ",
             "crypto store", call. = FALSE)
    }
    self_public <- mx.crypto::mxc_signing_key_public(keys$self_signing)
    signatures <- list()
    if (!mx_crypto_signature_valid(raw_device, client$user_id, self_public)) {
        # This endpoint adds signatures; include only the new one.
        raw_device$signatures <- NULL
        signatures[[client$device_id]] <- mx_crypto_add_signature(
            raw_device, keys$self_signing, client$user_id,
            paste0("ed25519:", self_public))
    }
    if (!mx_crypto_signature_valid(server_master, client$user_id, actual_ed,
                                   paste0("ed25519:", client$device_id))) {
        # Existing signatures stay on the server and need not be re-uploaded.
        master <- server_master %||% objects$master
        master$signatures <- NULL
        device_key_id <- paste0("ed25519:", client$device_id)
        master$signatures[[client$user_id]][[device_key_id]] <-
            mx.crypto::mxc_account_sign(
                device_account, mx_crypto_signable_json(master))
        signatures[[local_master]] <- master
    }
    if (length(signatures)) {
        response <- mx.api::mx_keys_signatures_upload(
            mx_client_session(client),
            stats::setNames(list(signatures), client$user_id))
        if (length(response$failures)) {
            stop("mx.client: homeserver rejected cross-signing signatures for ",
                 paste(names(response$failures), collapse = ", "), call. = FALSE)
        }
    }
    invisible(list(
        master = local_master, self_signing = self_public,
        user_signing = mx.crypto::mxc_signing_key_public(keys$user_signing)))
}
