library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    utils::packageVersion("mx.crypto") < "0.2.1.1" ||
    utils::packageVersion("mx.api") < "0.3.0.2") {
    exit_file("cross-signing dependencies are not available")
}
library(mx.client)

local({
UID <- "@tiny:example.org"
DEV <- "TINYDEV"
device <- mx.crypto::mxc_account_new()
store <- tempfile("cross-signing-")
dir.create(store, recursive = TRUE)
on.exit(unlink(store, recursive = TRUE), add = TRUE)

keys <- mx.client:::mx_crypto_cross_signing_new()
mx.client:::mx_crypto_cross_signing_save(keys, store)
loaded <- mx_crypto_cross_signing_load(store)
expect_identical(mx.crypto::mxc_signing_key_public(loaded$master),
                 mx.crypto::mxc_signing_key_public(keys$master))
expect_identical(as.octmode(file.info(file.path(
    store, "cross-signing.json"))$mode), as.octmode("600"))

objects <- mx.client:::mx_crypto_cross_signing_objects(
    loaded, UID, device, DEV)
master_public <- mx.client:::mx_crypto_cross_signing_public(
    objects$master, UID, "master")
self_public <- mx.client:::mx_crypto_cross_signing_public(
    objects$self_signing, UID, "self_signing")
expect_true(mx.client:::mx_crypto_signature_valid(
    objects$self_signing, UID, master_public))
expect_true(mx.client:::mx_crypto_signature_valid(
    objects$user_signing, UID, master_public))

raw_device <- mx_crypto_device_keys(device, UID, DEV)
signed_device <- mx.client:::mx_crypto_add_signature(
    raw_device, loaded$self_signing, UID, paste0("ed25519:", self_public))
chain <- mx.client:::mx_crypto_cross_signed_devices(
    setNames(list(setNames(list(signed_device), DEV)), UID),
    setNames(list(objects$master), UID),
    setNames(list(objects$self_signing), UID))
expect_identical(chain[[paste(UID, DEV, sep = "|")]], master_public)

# Our own chains must match the local master; another user's valid chain
# remains available even when the homeserver substitutes our identity.
local({
    other_uid <- "@peer:example.org"
    other_objects <- mx.client:::mx_crypto_cross_signing_objects(
        loaded, other_uid, device, DEV)
    other_device <- mx.client:::mx_crypto_add_signature(
        mx_crypto_device_keys(device, other_uid, DEV), loaded$self_signing,
        other_uid, paste0("ed25519:", self_public))
    response <- list(
        device_keys = setNames(list(setNames(list(signed_device), DEV),
                                    setNames(list(other_device), DEV)),
                               c(UID, other_uid)),
        master_keys = setNames(list(objects$master, other_objects$master),
                               c(UID, other_uid)),
        self_signing_keys = setNames(
            list(objects$self_signing, other_objects$self_signing),
            c(UID, other_uid)))
    original_query <- mx.api::mx_keys_query
    assignInNamespace("mx_keys_query", function(...) response, ns = "mx.api")
    on.exit(assignInNamespace("mx_keys_query", original_query, ns = "mx.api"))
    client <- list(server = "https://example.invalid", token = "tok",
                   user_id = UID, device_id = DEV)
    query <- function(pin = NULL) mx_crypto_known_devices(
        client, c(UID, other_uid), self_master_key = pin)
    trusted <- query(master_public)
    expect_true(trusted[[1]]$cross_signed)
    expect_true(trusted[[2]]$cross_signed)
    unpinned <- query()
    expect_false(unpinned[[1]]$cross_signed)
    expect_true(unpinned[[2]]$cross_signed)
    expect_identical(unpinned[[1]]$ed25519, trusted[[1]]$ed25519)

    # The replacement chain is cryptographically valid, but not our identity.
    forged_keys <- mx.client:::mx_crypto_cross_signing_new()
    forged <- mx.client:::mx_crypto_cross_signing_objects(
        forged_keys, UID, device, DEV)
    response$master_keys[[UID]] <- forged$master
    response$self_signing_keys[[UID]] <- forged$self_signing
    response$device_keys[[UID]][[DEV]] <- mx.client:::mx_crypto_add_signature(
        raw_device, forged_keys$self_signing, UID,
        paste0("ed25519:", mx.crypto::mxc_signing_key_public(
            forged_keys$self_signing)))
    replaced <- query(master_public)
    expect_false(replaced[[1]]$cross_signed)
    expect_true(replaced[[2]]$cross_signed)
    expect_identical(replaced[[1]]$master_key,
                     mx.crypto::mxc_signing_key_public(forged_keys$master))
    expect_identical(replaced[[1]]$curve25519, trusted[[1]]$curve25519)
    expect_true(query(replaced[[1]]$master_key)[[1]]$cross_signed)
})

# Tampering either link invalidates the chain.
bad_self <- objects$self_signing
bad_self$usage <- list("user_signing")
expect_warning(bad <- mx.client:::mx_crypto_cross_signed_devices(
    setNames(list(setNames(list(signed_device), DEV)), UID),
    setNames(list(objects$master), UID),
    setNames(list(bad_self), UID)))
expect_equal(length(bad), 0L)
bad_device <- signed_device
bad_device$algorithms <- list("m.megolm.v1.aes-sha2")
expect_equal(length(mx.client:::mx_crypto_cross_signed_devices(
    setNames(list(setNames(list(bad_device), DEV)), UID),
    setNames(list(objects$master), UID),
    setNames(list(objects$self_signing), UID))), 0L)

# Malformed signature bytes from one peer are invalid, not fatal.
malformed_device <- signed_device
malformed_device$signatures[[UID]][[paste0("ed25519:", self_public)]] <-
    "*** not base64 ***"
expect_false(mx.client:::mx_crypto_signature_valid(
    malformed_device, UID, self_public))
expect_equal(length(mx.client:::mx_crypto_cross_signed_devices(
    setNames(list(setNames(list(malformed_device), DEV)), UID),
    setNames(list(objects$master), UID),
    setNames(list(objects$self_signing), UID))), 0L)

# Bootstrap performs a UIA retry, then uploads master and device signatures.
local({
    client <- list(server = "https://example.invalid", token = "tok",
                   user_id = UID, device_id = DEV)
    fresh_store <- tempfile("bootstrap-")
    dir.create(fresh_store, recursive = TRUE)
    on.exit(unlink(fresh_store, recursive = TRUE), add = TRUE)
    uploaded <- list()
    signature_body <- NULL
    attempts <- 0L
    original_query <- mx.api::mx_keys_query
    original_cross <- mx.api::mx_keys_device_signing_upload
    original_signatures <- mx.api::mx_keys_signatures_upload
    signature_calls <- 0L
    current <- list(
        device_keys = setNames(list(setNames(list(raw_device), DEV)), UID),
        master_keys = list(), self_signing_keys = list())
    assignInNamespace("mx_keys_query", function(...) current, ns = "mx.api")
    assignInNamespace("mx_keys_device_signing_upload", function(
        session, master_key = NULL, self_signing_key = NULL,
        user_signing_key = NULL, auth = NULL) {
        attempts <<- attempts + 1L
        uploaded[[attempts]] <<- list(master = master_key, self = self_signing_key,
                                     user = user_signing_key, auth = auth)
        if (attempts == 1L) {
            cond <- structure(list(message = "UIA required", call = NULL,
                                   status = 401L, body = list(session = "uia-1")),
                              class = c("mx_error", "error", "condition"))
            stop(cond)
        }
        list()
    }, ns = "mx.api")
    assignInNamespace("mx_keys_signatures_upload", function(session, signatures) {
        signature_calls <<- signature_calls + 1L
        signature_body <<- signatures
        list(failures = list())
    }, ns = "mx.api")
    on.exit({
        assignInNamespace("mx_keys_query", original_query, ns = "mx.api")
        assignInNamespace("mx_keys_device_signing_upload", original_cross,
                          ns = "mx.api")
        assignInNamespace("mx_keys_signatures_upload", original_signatures,
                          ns = "mx.api")
    }, add = TRUE)

    result <- mx_crypto_cross_signing_bootstrap(
        client, device, fresh_store, password = "not-persisted")
    expect_equal(attempts, 2L)
    expect_null(uploaded[[1]]$auth)
    expect_identical(uploaded[[2]]$auth$session, "uia-1")
    expect_identical(uploaded[[2]]$auth$password, "not-persisted")
    expect_true(!is.null(signature_body[[UID]][[DEV]]))
    expect_true(!is.null(signature_body[[UID]][[result$master]]))
    persisted <- paste(readLines(file.path(fresh_store, "cross-signing.json"),
                                 warn = FALSE), collapse = "")
    expect_false(grepl("not-persisted", persisted, fixed = TRUE))

    # Reruns skip both signatures already reported by the server.
    current$master_keys[[UID]] <- signature_body[[UID]][[result$master]]
    current$self_signing_keys[[UID]] <- uploaded[[2]]$self
    # The upload endpoint merges signatures into the existing object.
    current$device_keys[[UID]][[DEV]] <- utils::modifyList(
        raw_device, signature_body[[UID]][[DEV]])
    complete <- current
    expect_identical(mx_crypto_cross_signing_bootstrap(
        client, device, fresh_store), result)
    expect_equal(signature_calls, 1L)
    expect_equal(attempts, 2L)

    # Upload only the missing link, preserving an existing valid signature.
    current$master_keys[[UID]]$signatures <- NULL
    current$master_keys[[UID]]$signatures[["@peer:example.org"]] <-
        list("ed25519:PEER" = "already-stored")
    mx_crypto_cross_signing_bootstrap(client, device, fresh_store)
    expect_equal(signature_calls, 2L)
    expect_identical(names(signature_body[[UID]]), result$master)
    expect_identical(names(signature_body[[UID]][[result$master]]$signatures), UID)
    expect_identical(names(signature_body[[UID]][[result$master]]$signatures[[UID]]),
                     paste0("ed25519:", DEV))
    expect_true(mx.client:::mx_crypto_signature_valid(
        signature_body[[UID]][[result$master]], UID,
        mx.crypto::mxc_account_identity_keys(device)$ed25519,
        paste0("ed25519:", DEV)))
    current <- complete
    current$device_keys[[UID]][[DEV]]$signatures[[UID]][[
        paste0("ed25519:", result$self_signing)]] <- "*** invalid ***"
    mx_crypto_cross_signing_bootstrap(client, device, fresh_store)
    expect_equal(signature_calls, 3L)
    expect_identical(names(signature_body[[UID]]), DEV)
    expect_identical(names(signature_body[[UID]][[DEV]]$signatures[[UID]]),
                     paste0("ed25519:", result$self_signing))
    expect_true(mx.client:::mx_crypto_signature_valid(
        signature_body[[UID]][[DEV]], UID, result$self_signing))

    # A published identity change is still refused before signature upload.
    current <- complete
    current$master_keys[[UID]] <- objects$master
    expect_error(mx_crypto_cross_signing_bootstrap(
        client, device, fresh_store), "master keys differ")
    expect_equal(signature_calls, 3L)
})
})
