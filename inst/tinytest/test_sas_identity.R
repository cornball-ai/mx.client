library(tinytest)
if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    !"mxc_sas_commitment" %in% getNamespaceExports("mx.crypto")) {
    exit_file("mx.crypto SAS primitives are unavailable")
}
library(mx.client)

local({
    ids <- c("@alice:example.org", "@bob:example.org")
    stores <- c(tempfile("sas-alice-"), tempfile("sas-bob-"))
    on.exit(unlink(stores, recursive = TRUE), add = TRUE)
    signing <- lapply(ids, function(x) mx.client:::mx_crypto_cross_signing_new())
    accounts <- lapply(ids, function(x) mx.crypto::mxc_account_new())
    clients <- lapply(ids, function(id) list(server = "https://example.invalid",
        token = "fixture", user_id = id, device_id = "DEVICE"))
    objects <- lapply(seq_along(ids), function(i) {
        mx.client:::mx_crypto_cross_signing_save(signing[[i]], stores[[i]])
        mx_crypto_account_save(accounts[[i]], stores[[i]])
        mx_crypto_sessions_save(mx_crypto_sessions_new(), stores[[i]])
        mx.client:::mx_crypto_cross_signing_objects(signing[[i]], ids[[i]],
            accounts[[i]], "DEVICE")
    })
    current <- list(
        master_keys = setNames(lapply(objects, `[[`, "master"), ids),
        self_signing_keys = setNames(lapply(objects, `[[`, "self_signing"), ids),
        user_signing_keys = setNames(lapply(objects, `[[`, "user_signing"), ids),
        device_keys = setNames(lapply(seq_along(ids), function(i) {
            list(DEVICE = mx_crypto_device_keys(accounts[[i]], ids[[i]], "DEVICE"))
        }), ids))
    pristine <- current
    queries <- uploads <- 0L
    mode <- "ok"
    original_query <- mx.api::mx_keys_query
    original_upload <- mx.api::mx_keys_signatures_upload
    on.exit({
        assignInNamespace("mx_keys_query", original_query, ns = "mx.api")
        assignInNamespace("mx_keys_signatures_upload", original_upload, ns = "mx.api")
    }, add = TRUE)
    assignInNamespace("mx_keys_query", function(session, ...) {
        queries <<- queries + 1L
        response <- current
        response$user_signing_keys <- response$user_signing_keys[session$user_id]
        response
    }, ns = "mx.api")
    assignInNamespace("mx_keys_signatures_upload", function(session, signatures) {
        uploads <<- uploads + 1L
        if (mode == "reject") return(list(failures = list(peer = "rejected")))
        if (mode == "drop") return(list())
        for (uid in names(signatures)) for (key in names(signatures[[uid]])) {
            current$master_keys[[uid]]$signatures[[session$user_id]] <<-
                signatures[[uid]][[key]]$signatures[[session$user_id]]
        }
        list()
    }, ns = "mx.api")
    request <- function() list(type = "m.room.message", sender = ids[2],
        room_id = "!room:example.org", event_id = "$request",
        origin_server_ts = as.numeric(Sys.time()) * 1000,
        content = list(msgtype = "m.key.verification.request", to = ids[1],
            body = "Verify", methods = list("m.sas.v1"), from_device = "DEVICE"))
    from <- function(event = request()) mx_sas_from_request(clients[[1]], stores[1], event)
    sas <- from()
    expect_inherits(sas, "mx_sas")
    expect_identical(mx_sas_status(sas)$phase, "requested")
    expect_equal(queries, 2L)
    expect_equal(uploads, 0L)
    files <- unlist(lapply(stores, list.files, full.names = TRUE))
    before <- tools::md5sum(files)

    for (fault in c("old", "future", "time", "recipient", "method", "own", "device")) {
        ev <- request()
        if (fault == "old") ev$origin_server_ts <- ev$origin_server_ts - 601000
        if (fault == "future") ev$origin_server_ts <- ev$origin_server_ts + 301000
        if (fault == "time") ev$origin_server_ts <- "not a timestamp"
        if (fault == "recipient") ev$content$to <- "@other:example.org"
        if (fault == "method") ev$content$methods <- list("m.qr_code.show.v1")
        if (fault == "own") ev$sender <- ids[1]
        if (fault == "device") ev$content$from_device <- NULL
        expect_null(from(ev))
    }
    expect_equal(queries, 2L)
    ev <- request()
    ev$room_id <- NULL
    ev$type <- "m.key.verification.request"
    ev$content$timestamp <- ev$origin_server_ts
    ev$content$transaction_id <- "to-device-request"
    expect_inherits(from(ev), "mx_sas")
    absent <- tempfile("sas-no-store-")
    expect_error(mx_sas_from_request(clients[[1]], absent, request()), "existing crypto store")
    expect_false(dir.exists(absent))
    current$master_keys[[ids[1]]] <- objects[[2]]$master
    expect_error(from(), "master")
    current <- pristine
    current$device_keys[[ids[1]]]$DEVICE <- mx_crypto_device_keys(
        accounts[[2]], ids[1], "DEVICE")
    expect_error(from(), "device keys differ")
    current <- pristine
    current$user_signing_keys[[ids[1]]]$signatures <- list()
    expect_error(from(), "user-signing key")
    current <- pristine
    expect_identical(tools::md5sum(files), before)
    expect_equal(uploads, 0L)

    make_pair <- function() {
        a <- from()
        b <- mx_sas_session(ids[2], "DEVICE", a$peer_keys, ids[1], "DEVICE",
            a$keys, a$transaction_id, a$room_id, initiator = TRUE)
        list(a = a, b = b)
    }
    transfer <- function(from, to) {
        for (e in mx_sas_outgoing(from)) {
            mx_sas_receive(to, list(sender = from$user_id, room_id = e$room_id,
                type = e$type, content = e$content))
            mx_sas_outgoing(from, e$id)
        }
    }
    exchange <- function(p) {
        mx_sas_accept(p$a)
        for (i in 1:3) {transfer(p$a, p$b); transfer(p$b, p$a)}
        mx_sas_confirm(p$a, TRUE)
        mx_sas_confirm(p$b, TRUE)
        transfer(p$a, p$b)
        transfer(p$b, p$a)
        p
    }
    p <- exchange(make_pair())
    expect_identical(mx_sas_status(p$a)$phase, "verified")
    mx_sas_record_trust(p$a, clients[[1]], stores[1])
    expect_true(mx_sas_status(p$a)$local_trust_recorded)
    expect_false(mx_sas_status(p$a)$peer_done)
    expect_equal(uploads, 1L)
    mx_sas_record_trust(p$a, clients[[1]], stores[1])
    expect_equal(uploads, 1L)
    transfer(p$a, p$b)
    mx_sas_record_trust(p$b, clients[[2]], stores[2])
    transfer(p$b, p$a)
    expect_identical(mx_sas_status(p$a)$phase, "done")
    expect_identical(mx_sas_status(p$b)$phase, "done")
    expect_equal(uploads, 2L)
    for (i in 1:2) expect_true(mx_crypto_user_trust(clients[[i]], stores[i], ids[3-i],
        mx.crypto::mxc_signing_key_public(signing[[3-i]]$master))$verified)

    # Changed keys cancel before any new upload. A fresh valid exchange succeeds above.
    current <- pristine
    p <- exchange(make_pair())
    current$device_keys[[ids[2]]]$DEVICE <- mx_crypto_device_keys(
        accounts[[1]], ids[2], "DEVICE")
    expect_error(mx_sas_record_trust(p$a, clients[[1]], stores[1]), "keys changed")
    expect_equal(uploads, 2L)
    expect_identical(mx_sas_status(p$a)$cancel_code, "m.key_mismatch")
    current <- pristine
    p <- exchange(make_pair())
    mode <- "reject"
    expect_error(mx_sas_record_trust(p$a, clients[[1]], stores[1]), "rejected")
    expect_false(mx_sas_status(p$a)$local_trust_recorded)
    mode <- "drop"
    expect_error(mx_sas_record_trust(p$a, clients[[1]], stores[1]), "not confirmed")
    expect_false(mx_sas_status(p$a)$local_trust_recorded)
    mode <- "ok"
    mx_sas_record_trust(p$a, clients[[1]], stores[1])
    expect_true(mx_sas_status(p$a)$local_trust_recorded)

    # The console drives real protocol and trust code, with synthetic human input.
    current <- pristine
    p <- make_pair()
    prompts <- receives <- sends <- completes <- 0L
    input <- function(prompt) {prompts <<- prompts + 1L; "yes"}
    send <- function(e) {
        sends <<- sends + 1L
        mx_sas_receive(p$b, list(type = e$type, content = e$content,
            room_id = e$room_id, sender = ids[1]))
    }
    receive <- function() {
        receives <<- receives + 1L
        if (identical(p$b$phase, "sas")) mx_sas_confirm(p$b, TRUE)
        if (identical(p$b$phase, "verified") && !p$b$local_trust_recorded) {
            mx_sas_record_trust(p$b, clients[[2]], stores[2])
        }
        out <- mx_sas_outgoing(p$b)
        for (e in out) mx_sas_outgoing(p$b, e$id)
        lapply(out, function(e) list(type = e$type, content = e$content,
            room_id = e$room_id, sender = ids[2]))
    }
    complete <- function(sas) {
        completes <<- completes + 1L
        mx_sas_record_trust(sas, clients[[1]], stores[1])
    }
    result <- suppressMessages(mx_sas_console(p$a, receive, send, complete, input))
    expect_identical(result$phase, "done")
    expect_true(result$local_trust_recorded)
    expect_equal(prompts, 2L)
    expect_true(receives >= 4L)
    expect_true(sends >= 4L)
    expect_equal(completes, 1L)
    expect_error(mx_verify_console(NULL, NULL, NULL), "exclusive = TRUE")
    expect_identical(tools::md5sum(files), before)

    # Standalone ownership preflight checks both token and existing store.
    cfg_path <- file.path(stores[1], "client.json")
    cfg <- mx_client_save(mx_client_from_config(clients[[1]], path = cfg_path))
    whoami <- mx.api::mx_whoami
    sync <- mx.api::mx_sync
    save_account <- mx_crypto_account_save
    save_sessions <- mx_crypto_sessions_save
    save_client <- mx_client_save
    on.exit({
        assignInNamespace("mx_whoami", whoami, "mx.api")
        assignInNamespace("mx_sync", sync, "mx.api")
        assignInNamespace("mx_crypto_account_save", save_account, "mx.client")
        assignInNamespace("mx_crypto_sessions_save", save_sessions, "mx.client")
        assignInNamespace("mx_client_save", save_client, "mx.client")
    }, add = TRUE)
    identity_calls <- 0L
    wrong_identity <- FALSE
    assignInNamespace("mx_whoami", function(session) {
        identity_calls <<- identity_calls + 1L
        list(user_id = ids[1], device_id = if (wrong_identity) "OTHER" else "DEVICE")
    }, "mx.api")
    ctx <- mx.client:::verification_context(cfg, stores[1])
    expect_true(is.environment(ctx))
    expect_equal(identity_calls, 1L)
    wrong_identity <- TRUE
    expect_error(mx.client:::verification_context(cfg, stores[1]), "different Matrix device")
    wrong_identity <- FALSE
    current$self_signing_keys[[ids[1]]]$signatures <- list()
    expect_error(mx.client:::verification_context(cfg, stores[1]), "self-signing key")
    current <- pristine

    # A real encrypted batch survives to the verification queue; its ordinary
    # message callback runs only after account, sessions, and cursor are saved.
    ak <- mx.crypto::mxc_account_identity_keys(ctx$account)
    bk <- mx.crypto::mxc_account_identity_keys(accounts[[2]])
    mx.crypto::mxc_account_generate_one_time_keys(ctx$account, 1L)
    recipient <- list(user_id = ids[1], device_id = "DEVICE",
        curve25519 = ak$curve25519, ed25519 = ak$ed25519,
        otk = mx.crypto::mxc_account_one_time_keys(ctx$account)[[1]])
    room <- "!room:example.org"
    out <- mx_crypto_encrypt_for_devices(accounts[[2]], mx_crypto_sessions_new(),
        room, request()$content, bk$curve25519, "DEVICE", list(recipient), ids[2])
    normal <- mx_crypto_encrypt_for_devices(accounts[[2]], out$sessions, room,
        list(msgtype = "m.text", body = "ordinary fixture"), bk$curve25519,
        "DEVICE", list(recipient), ids[2])
    batch <- list(next_batch = "after-verification", to_device = list(events =
        lapply(out$to_device, function(p) list(type = "m.room.encrypted",
            sender = ids[2], content = p$content))), rooms = list(join = setNames(
        list(list(timeline = list(events = lapply(list(out$event, normal$event),
            function(c) list(type = "m.room.encrypted", sender = ids[2],
                event_id = "$fixture", origin_server_ts = 100000, content = c))))), room)))
    sequence <- character()
    assignInNamespace("mx_sync", function(...) {
        sequence <<- c(sequence, "sync"); batch
    }, "mx.api")
    assignInNamespace("mx_crypto_account_save", function(...) {
        sequence <<- c(sequence, "account"); save_account(...)
    }, "mx.client")
    assignInNamespace("mx_crypto_sessions_save", function(...) {
        sequence <<- c(sequence, "sessions"); save_sessions(...)
    }, "mx.client")
    assignInNamespace("mx_client_save", function(...) {
        sequence <<- c(sequence, "cursor"); save_client(...)
    }, "mx.client")
    events <- mx.client:::verification_poll(ctx, ids[2], function(messages) {
        sequence <<- c(sequence, "messages")
        expect_identical(mx_client_load(path = cfg_path)$sync_token, "after-verification")
        expect_equal(length(mx_crypto_sessions_load(stores[1])$megolm_in), 1L)
        expect_identical(messages[[1]]$body, "ordinary fixture")
    })
    expect_identical(sequence, c("sync", "account", "sessions", "cursor", "messages"))
    expect_equal(length(events), 1L)
    expect_identical(events[[1]]$content$msgtype, "m.key.verification.request")
    expect_equal(length(ctx$messages), 1L)

    # Reusing the caller's original object must not rewind the saved cursor.
    # The bot and original console may both have advanced it since loading.
    expect_null(cfg$sync_token)
    retry_ctx <- mx.client:::verification_context(cfg, stores[1])
    expect_identical(retry_ctx$client$sync_token, "after-verification")
    resumed_since <- NULL
    sync_calls <- 0L
    assignInNamespace("mx_sync", function(session, since = NULL, ...) {
        sync_calls <<- sync_calls + 1L
        resumed_since <<- since
        list(next_batch = "after-retry")
    }, "mx.api")
    mx.client:::verification_poll(retry_ctx, ids[2], function(e) NULL)
    expect_equal(sync_calls, 1L)
    expect_identical(resumed_since, "after-verification")
    expect_identical(mx_client_load(path = cfg_path)$sync_token, "after-retry")

    # A fresh cursor is not permission to silently switch device or server.
    saved <- mx_client_load(path = cfg_path)
    before_calls <- identity_calls
    for (field in c("server", "user_id", "device_id")) {
        changed <- saved
        changed[[field]] <- paste0(changed[[field]], "-changed")
        mx_client_save(changed)
        expect_error(mx.client:::verification_context(cfg, stores[1]),
            "saved Matrix identity changed")
    }
    expect_equal(identity_calls, before_calls)
    mx_client_save(saved)
})
