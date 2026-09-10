library(tinytest)
if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    utils::packageVersion("mx.crypto") < "0.2.1.1" ||
    utils::packageVersion("mx.api") < "0.3.0.2") {
    exit_file("cross-signing dependencies are not available")
}
library(mx.client)

local({
    ids <- c("@alice:example.org", "@bob:example.org")
    stores <- c(tempfile("alice-"), tempfile("bob-"))
    on.exit(unlink(stores, recursive = TRUE), add = TRUE)
    keys <- lapply(ids, function(x) mx.client:::mx_crypto_cross_signing_new())
    accounts <- lapply(ids, function(x) mx.crypto::mxc_account_new())
    clients <- lapply(ids, function(id) list(server = "https://example.invalid",
        token = "fixture-token", user_id = id, device_id = "DEVICE"))
    objects <- lapply(seq_along(ids), function(i) {
        mx.client:::mx_crypto_cross_signing_save(keys[[i]], stores[[i]])
        mx_crypto_account_save(accounts[[i]], stores[[i]])
        mx_crypto_sessions_save(mx_crypto_sessions_new(), stores[[i]])
        mx.client:::mx_crypto_cross_signing_objects(
            keys[[i]], ids[[i]], accounts[[i]], "DEVICE")
    })
    pins <- vapply(keys, function(k) mx.crypto::mxc_signing_key_public(k$master),
                   character(1))
    users <- vapply(keys, function(k)
        mx.crypto::mxc_signing_key_public(k$user_signing), character(1))
    current <- list(
        master_keys = setNames(lapply(objects, `[[`, "master"), ids),
        self_signing_keys = setNames(lapply(objects, `[[`, "self_signing"), ids),
        user_signing_keys = setNames(lapply(objects, `[[`, "user_signing"), ids),
        device_keys = setNames(lapply(seq_along(ids), function(i) {
            device <- mx_crypto_device_keys(accounts[[i]], ids[[i]], "DEVICE")
            setNames(list(mx.client:::mx_crypto_add_signature(
                device, keys[[i]]$self_signing, ids[[i]], paste0("ed25519:",
                    mx.crypto::mxc_signing_key_public(keys[[i]]$self_signing)))),
                "DEVICE")
        }), ids))
    pristine <- current
    calls <- list()
    queries <- 0L
    query_names <- NULL
    mode <- "ok"
    query_original <- mx.api::mx_keys_query
    upload_original <- mx.api::mx_keys_signatures_upload
    on.exit({
        assignInNamespace("mx_keys_query", query_original, ns = "mx.api")
        assignInNamespace("mx_keys_signatures_upload", upload_original,
                          ns = "mx.api")
    }, add = TRUE)
    assignInNamespace("mx_keys_query", function(session, device_keys, ...) {
        queries <<- queries + 1L
        query_names <<- names(device_keys)
        result <- current
        # The protocol returns only the requesting user's user-signing key.
        result$user_signing_keys <- result$user_signing_keys[session$user_id]
        result
    }, ns = "mx.api")
    assignInNamespace("mx_keys_signatures_upload", function(session, signatures) {
        calls[[length(calls) + 1L]] <<- signatures
        if (mode == "transport") stop("fixture transport failure")
        if (mode == "reject") return(list(failures = list(peer = "rejected")))
        if (mode == "drop") return(list())
        for (uid in names(signatures)) {
            for (key in names(signatures[[uid]])) {
                incoming <- signatures[[uid]][[key]]
                current$master_keys[[uid]]$signatures[[session$user_id]] <<-
                    incoming$signatures[[session$user_id]]
            }
        }
        list(failures = list())
    }, ns = "mx.api")
    check <- function(i = 1L) {
        j <- 3L - i
        mx_crypto_user_trust(clients[[i]], stores[[i]], ids[[j]], pins[[j]])
    }
    verify <- function(i = 1L) {
        j <- 3L - i
        mx_crypto_verify_user(clients[[i]], stores[[i]], ids[[j]], pins[[j]])
    }
    devices <- function(pin = pins[[1]]) mx_crypto_known_devices(
        clients[[1]], ids[[2]], self_master_key = pin)
    store_files <- unlist(lapply(stores, list.files, full.names = TRUE))
    before <- tools::md5sum(store_files)

    # Neither valid device chains nor a read-only check grants user trust.
    expect_false(check(1L)$verified)
    expect_false(check(2L)$verified)
    expect_equal(length(calls), 0L)
    expect_equal(queries, 2L)
    expect_true(devices()[[1]]$cross_signed)
    expect_false(devices()[[1]]$identity_verified)

    # One real Ed25519 signature establishes only Alice -> Bob.
    alice <- verify(1L)
    expect_true(alice$verified)
    expect_identical(alice$signer_user_id, ids[[1]])
    expect_false(check(2L)$verified)
    expect_equal(length(calls), 1L)
    payload <- calls[[1]][[ids[[2]]]][[pins[[2]]]]
    expect_identical(names(calls[[1]]), ids[[2]])
    expect_identical(names(calls[[1]][[ids[[2]]]]), pins[[2]])
    expect_identical(names(payload$signatures), ids[[1]])
    expect_true(mx.crypto::mxc_ed25519_verify(users[[1]],
        charToRaw(mx.api::mx_canonical_json(within(payload, rm(signatures)))),
        payload$signatures[[ids[[1]]]][[paste0("ed25519:", users[[1]])]]))
    expect_identical(verify(1L), alice)
    expect_equal(length(calls), 1L)
    expect_true(devices()[[1]]$identity_verified)
    expect_identical(query_names, rev(ids))
    expect_equal(length(devices()), 1L)
    expect_false(devices(NULL)[[1]]$identity_verified)
    expect_false(devices(pins[[2]])[[1]]$identity_verified)

    # The second account signs independently. Both checks survive reload.
    expect_true(verify(2L)$verified)
    expect_true(check(1L)$verified)
    expect_true(check(2L)$verified)
    expect_equal(length(calls), 2L)
    complete <- current
    expect_identical(tools::md5sum(store_files), before)

    # User trust does not turn an unsigned or substituted device into trusted.
    current$device_keys[[ids[[2]]]][["DEVICE"]] <-
        mx_crypto_device_keys(accounts[[2]], ids[[2]], "DEVICE")
    expect_false(devices()[[1]]$identity_verified)
    expect_true(check(1L)$verified)
    current <- complete
    current$user_signing_keys[[ids[[1]]]]$signatures <- list()
    expect_false(devices()[[1]]$identity_verified)
    expect_error(verify(), "user-signing key")
    expect_equal(length(calls), 2L)
    current <- complete
    current$master_keys[[ids[[2]]]]$signatures[[ids[[1]]]][[
        paste0("ed25519:", users[[1]])]] <- "***bad-base64***"
    expect_false(check()$verified)
    expect_false(devices()[[1]]$identity_verified)
    expect_true(verify()$verified)
    expect_equal(length(calls), 3L)

    # A coherent replacement identity still cannot replace either pin.
    current <- complete
    forged <- mx.client:::mx_crypto_cross_signing_new()
    replacement <- mx.client:::mx_crypto_cross_signing_objects(
        forged, ids[[2]], accounts[[2]], "DEVICE")
    current$master_keys[[ids[[2]]]] <- replacement$master
    expect_error(verify(), "peer master key differs")
    expect_warning(replaced_devices <- devices(), "invalid cross-signing chain")
    expect_false(replaced_devices[[1]]$identity_verified)
    current <- complete
    current$master_keys[[ids[[1]]]] <- mx.client:::mx_crypto_cross_signing_objects(
        forged, ids[[1]], accounts[[1]], "DEVICE")$master
    expect_error(verify(), "local and homeserver master keys differ")
    expect_false(devices()[[1]]$identity_verified)
    current <- complete
    current$failures <- list("example.org" = list(errcode = "M_TIMEOUT"))
    expect_error(verify(), "could not reach")
    expect_equal(length(calls), 3L)

    # Transport success alone must never report verified.
    current <- pristine
    mode <- "reject"
    expect_error(verify(), "rejected")
    expect_false(check()$verified)
    mode <- "drop"
    expect_error(verify(), "not confirmed")
    expect_false(check()$verified)
    mode <- "transport"
    expect_error(verify(), "fixture transport failure")
    expect_false(check()$verified)
    mode <- "ok"
    expect_true(verify()$verified)
    expect_equal(length(calls), 7L)

    # Refuse incomplete stores and invalid inputs before any network I/O.
    nquery <- queries
    empty <- tempfile("missing-identity-")
    on.exit(unlink(empty, recursive = TRUE), add = TRUE)
    expect_error(mx_crypto_verify_user(clients[[1]], empty, ids[[2]], pins[[2]]),
                 "existing cross-signing store")
    expect_false(dir.exists(empty))
    dir.create(empty)
    file.copy(file.path(stores[[1]], "cross-signing.json"), empty)
    expect_error(mx_crypto_verify_user(clients[[1]], empty, ids[[2]], pins[[2]]),
                 "existing cross-signing store")
    expect_false(file.exists(file.path(empty, "pickle.key")))
    expect_error(mx_crypto_verify_user(clients[[1]], stores[[1]], ids[[1]], pins[[1]]),
                 "different Matrix user")
    for (pin in list(NULL, NA_character_, "short", c(pins[[1]], pins[[2]]))) {
        expect_error(mx_crypto_verify_user(clients[[1]], stores[[1]], ids[[2]], pin),
                     "full independently verified")
    }
    expect_equal(queries, nquery)
    expect_equal(length(calls), 7L)
    expect_identical(tools::md5sum(store_files), before)
})
