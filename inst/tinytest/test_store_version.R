library(tinytest)
library(mx.client)

if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    utils::packageVersion("mx.crypto") < "0.2.2") {
    exit_file("mx.crypto >= 0.2.2 required")
}

local({
    store <- tempfile("mx-schema-")
    dir.create(store)
    on.exit(unlink(store, recursive = TRUE), add = TRUE)
    read_blob <- function(path) {
        jsonlite::fromJSON(paste(readLines(path), collapse = "\n"),
            simplifyVector = FALSE)
    }
    write_blob <- function(blob, path) {
        writeLines(jsonlite::toJSON(blob, auto_unbox = TRUE, null = "null"), path)
    }
    account <- mx_crypto_account(store)
    identity <- mx.crypto::mxc_account_identity_keys(account)
    account_path <- file.path(store, "account.pickle")
    key <- mx.client:::mx_crypto_key(store)
    read_raw <- function() {
        pickle <- paste(readLines(account_path), collapse = "")
        expect_false(startsWith(trimws(pickle), "{"))
        # Same decode path used by older mx.client versions.
        mx.crypto::mxc_account_unpickle(pickle, key)
    }
    expect_identical(mx.crypto::mxc_account_identity_keys(read_raw()), identity)
    expect_identical(mx.crypto::mxc_account_identity_keys(
        mx_crypto_account(store)), identity)

    # The API returns a named map; ordering is not part of the key identity.
    read_otks <- function(account) {
        keys <- mx.crypto::mxc_account_one_time_keys(account)
        keys[sort(names(keys))]
    }
    # One-time-key replenishment must not change the account's file format.
    mx.crypto::mxc_account_generate_one_time_keys(account, 2L)
    one_time_keys <- read_otks(account)
    expect_identical(length(one_time_keys), 2L)
    mx_crypto_account_save(account, store)
    loaded <- read_raw()
    expect_identical(mx.crypto::mxc_account_identity_keys(loaded), identity)
    expect_identical(read_otks(loaded), one_time_keys)

    # Raw base64 remains raw on save, and loading never rewrites it.
    legacy <- mx.crypto::mxc_account_pickle(account, key)
    writeLines(legacy, account_path)
    before <- tools::md5sum(account_path)
    loaded <- mx_crypto_account(store)
    expect_identical(mx.crypto::mxc_account_identity_keys(loaded), identity)
    expect_identical(tools::md5sum(account_path), before)
    mx_crypto_account_save(loaded, store)
    expect_identical(mx.crypto::mxc_account_identity_keys(read_raw()), identity)

    # Explicit envelopes still load without rewriting. A later save writes raw.
    account_blob <- list(version = 1L, pickle = legacy)
    write_blob(account_blob, account_path)
    before <- tools::md5sum(account_path)
    loaded <- mx_crypto_account(store)
    expect_identical(mx.crypto::mxc_account_identity_keys(loaded), identity)
    expect_identical(tools::md5sum(account_path), before)
    mx_crypto_account_save(loaded, store)
    loaded <- read_raw()
    expect_identical(mx.crypto::mxc_account_identity_keys(loaded), identity)
    expect_identical(read_otks(loaded), one_time_keys)
    write_blob(account_blob, account_path)

    # A real Megolm session and pending request survive both formats.
    sessions <- mx_crypto_sessions_new()
    group <- mx.crypto::mxc_megolm_outbound_new()
    info <- mx.crypto::mxc_megolm_outbound_info(group)
    sessions$megolm_out[["!room:example.org"]] <- list(
        session = group, shared = character())
    sessions$key_requests$fixture <- list(request_id = "fixture", sent = FALSE)
    mx_crypto_sessions_save(sessions, store)
    sessions_path <- file.path(store, "sessions.json")
    sessions_blob <- read_blob(sessions_path)
    expect_identical(sessions_blob$version, 1L)
    for (versioned in c(TRUE, FALSE)) {
        blob <- sessions_blob
        if (!versioned) blob$version <- NULL
        write_blob(blob, sessions_path)
        before <- tools::md5sum(sessions_path)
        loaded <- mx_crypto_sessions_load(store)
        expect_identical(mx.crypto::mxc_megolm_outbound_info(
            loaded$megolm_out[["!room:example.org"]]$session)$session_id,
            info$session_id)
        expect_identical(loaded$key_requests, sessions$key_requests)
        expect_identical(tools::md5sum(sessions_path), before)
    }
    # Old four-map stores predate key requests.
    sessions_blob$version <- NULL
    sessions_blob$key_requests <- NULL
    write_blob(sessions_blob, sessions_path)
    expect_identical(mx_crypto_sessions_load(store)$key_requests, list())
    mx_crypto_sessions_save(mx_crypto_sessions_load(store), store)
    expect_identical(read_blob(sessions_path)$version, 1L)

    signing <- mx.client:::mx_crypto_cross_signing_new()
    mx.client:::mx_crypto_cross_signing_save(signing, store)
    signing_path <- file.path(store, "cross-signing.json")
    signing_blob <- read_blob(signing_path)
    expect_identical(signing_blob$version, 1L)
    expect_identical(mx.crypto::mxc_signing_key_public(
        mx_crypto_cross_signing_load(store)$master),
        mx.crypto::mxc_signing_key_public(signing$master))

    # Never coerce malformed versions (1.5, TRUE, "1", [1]) into version 1.
    paths <- c(account_path, sessions_path, signing_path)
    loaders <- list(mx_crypto_account, mx_crypto_sessions_load,
        mx_crypto_cross_signing_load)
    blobs <- lapply(paths, read_blob)
    for (i in seq_along(paths)) {
        for (version in list(2L, 0L, -1L, 1.5, TRUE, "1", list(1L), NULL)) {
            blob <- blobs[[i]]
            blob["version"] <- list(version)
            write_blob(blob, paths[[i]])
            before <- tools::md5sum(paths)
            expect_error(loaders[[i]](store), "schema version")
            error <- tryCatch(loaders[[i]](store), error = function(e) e)
            expect_true(grepl(paths[[i]], conditionMessage(error),
                fixed = TRUE))
            expect_identical(tools::md5sum(paths), before)
        }
        write_blob(blobs[[i]], paths[[i]])
    }

    # Cross-signing and JSON account envelopes never had a versionless form.
    for (i in c(1L, 3L)) {
        blob <- blobs[[i]]
        blob$version <- NULL
        write_blob(blob, paths[[i]])
        expect_error(loaders[[i]](store), "schema version")
        write_blob(blobs[[i]], paths[[i]])
    }
    malformed <- list(version = 1L, pickle = list())
    write_blob(malformed, account_path)
    expect_error(mx_crypto_account(store), "expected an encrypted pickle")
    error <- tryCatch(mx_crypto_account(store), error = function(e) e)
    expect_true(grepl(account_path, conditionMessage(error), fixed = TRUE))

    # Unsupported versions are checked before any key file is created.
    missing_key <- file.path(store, "without-key")
    dir.create(missing_key)
    for (i in seq_along(paths)) {
        blob <- blobs[[i]]
        blob$version <- 2L
        write_blob(blob, file.path(missing_key, basename(paths[[i]])))
        expect_error(loaders[[i]](missing_key), "schema version")
        expect_false(file.exists(file.path(missing_key, "pickle.key")))
    }
})
