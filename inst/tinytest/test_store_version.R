library(tinytest)
library(mx.client)

if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    utils::packageVersion("mx.crypto") < "0.2.1.2") {
    exit_file("mx.crypto >= 0.2.1.2 required")
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
    account_blob <- read_blob(account_path)
    expect_identical(account_blob$version, 1L)
    expect_identical(mx.crypto::mxc_account_identity_keys(
        mx_crypto_account(store)), identity)

    # Legacy base64 is read as-is and becomes versioned only on save.
    key <- mx.client:::mx_crypto_key(store)
    legacy <- mx.crypto::mxc_account_pickle(account, key)
    writeLines(legacy, account_path)
    before <- tools::md5sum(account_path)
    loaded <- mx_crypto_account(store)
    expect_identical(mx.crypto::mxc_account_identity_keys(loaded), identity)
    expect_identical(tools::md5sum(account_path), before)
    mx_crypto_account_save(loaded, store)
    expect_identical(read_blob(account_path)$version, 1L)
    expect_identical(mx.crypto::mxc_account_identity_keys(
        mx_crypto_account(store)), identity)

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
