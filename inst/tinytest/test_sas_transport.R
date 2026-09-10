library(tinytest)
if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    !"mxc_sas_commitment" %in% getNamespaceExports("mx.crypto")) {
    exit_file("mx.crypto SAS primitives are unavailable")
}
library(mx.client)

local({
    a <- mx.crypto::mxc_account_new()
    b <- mx.crypto::mxc_account_new()
    ak <- mx.crypto::mxc_account_identity_keys(a)
    bk <- mx.crypto::mxc_account_identity_keys(b)
    mx.crypto::mxc_account_generate_one_time_keys(b, 1L)
    recipient <- list(user_id = "@bob:example.org", device_id = "B",
        curve25519 = bk$curve25519, ed25519 = bk$ed25519,
        otk = mx.crypto::mxc_account_one_time_keys(b)[[1]])
    room <- "!room:example.org"
    relation <- list(rel_type = "m.reference", event_id = "$request")
    content <- list(from_device = "A", methods = list("m.sas.v1"),
        `m.relates_to` = relation)
    out <- mx_crypto_encrypt_for_devices(a, mx_crypto_sessions_new(), room,
        content, ak$curve25519, "A", list(recipient), "@alice:example.org",
        event_type = "m.key.verification.ready")
    expect_identical(out$event$`m.relates_to`, relation)
    expect_equal(length(out$to_device), 1L)
    event <- list(type = "m.room.encrypted", sender = "@alice:example.org",
        event_id = "$ready", origin_server_ts = 100000, content = out$event)
    response <- list(to_device = list(events = lapply(out$to_device, function(p)
        list(type = "m.room.encrypted", sender = "@alice:example.org", content = p$content))),
        rooms = list(join = setNames(list(list(timeline = list(events = list(event)))), room)))
    devices <- list(list(user_id = "@alice:example.org", device_id = "A",
        curve25519 = ak$curve25519, ed25519 = ak$ed25519))
    res <- mx_crypto_process_sync(b, mx_crypto_sessions_new(), response,
        bk$curve25519, "@bob:example.org", devices, "B")
    expect_equal(length(res$events), 0L)
    expect_equal(length(res$verification_events), 1L)
    ready <- res$verification_events[[1]]
    expect_identical(ready$type, "m.key.verification.ready")
    expect_identical(mx.api::mx_canonical_json(ready$content),
        mx.api::mx_canonical_json(content))
    expect_identical(ready$event_id, "$ready")
    expect_identical(ready$origin_server_ts, event$origin_server_ts)
    expect_true(ready$sender_verified)

    # Matrix Dart SDK moves the relation outside the encrypted plaintext.
    encrypt_outer <- function(inner_room = room, inner_relation = NULL) {
        plaintext <- list(type = "m.key.verification.start", room_id = inner_room,
            content = list(from_device = "A", method = "m.sas.v1"))
        plaintext$content$`m.relates_to` <- inner_relation
        event$content$ciphertext <- mx.crypto::mxc_megolm_encrypt(
            out$sessions$megolm_out[[room]]$session,
            charToRaw(mx.api::mx_canonical_json(plaintext)))
        response$to_device$events <- list()
        response$rooms$join[[room]]$timeline$events <- list(event)
        response
    }
    processed <- mx_crypto_process_sync(b, res$sessions, encrypt_outer(),
        bk$curve25519, "@bob:example.org", devices, "B")
    expect_identical(processed$verification_events[[1]]$content$`m.relates_to`, relation)
    wrong <- encrypt_outer(inner_relation = list(rel_type = "m.reference", event_id = "$other"))
    expect_warning(rejected <- mx_crypto_process_sync(b, res$sessions, wrong,
        bk$curve25519, "@bob:example.org", devices, "B"), "conflicting relations")
    expect_equal(length(rejected$verification_events), 0L)
    # Canonicalization errors from untrusted outer metadata cannot abort sync.
    bad <- encrypt_outer(inner_relation = relation)
    bad$rooms$join[[room]]$timeline$events[[1]]$content$`m.relates_to`$extra <- 0.5
    good <- encrypt_outer()
    bad$rooms$join[[room]]$timeline$events <- c(
        bad$rooms$join[[room]]$timeline$events,
        good$rooms$join[[room]]$timeline$events)
    expect_warning(continued <- mx_crypto_process_sync(b, res$sessions, bad,
        bk$curve25519, "@bob:example.org", devices, "B"), "conflicting relations")
    expect_equal(length(continued$verification_events), 1L)
    expect_identical(continued$verification_events[[1]]$type, "m.key.verification.start")
    wrong <- encrypt_outer(inner_room = "!other:example.org")
    expect_warning(rejected <- mx_crypto_process_sync(b, res$sessions, wrong,
        bk$curve25519, "@bob:example.org", devices, "B"), "different room")
    expect_equal(length(rejected$verification_events), 0L)

    # Clear room and to-device requests remain original envelopes, not chat text.
    request <- list(type = "m.room.message", sender = "@alice:example.org",
        event_id = "$req", origin_server_ts = 100000,
        content = list(msgtype = "m.key.verification.request", body = "Verify",
            to = "@bob:example.org", from_device = "A", methods = list("m.sas.v1")))
    td <- list(type = "m.key.verification.request", sender = "@alice:example.org",
        content = list(from_device = "A", methods = list("m.sas.v1"),
            transaction_id = "td", timestamp = 100000))
    response$to_device$events <- list(td)
    response$rooms$join[[room]]$timeline$events <- list(request)
    plain <- mx_crypto_process_sync(b, res$sessions, response,
        bk$curve25519, "@bob:example.org", devices, "B")
    expect_equal(length(plain$events), 0L)
    expect_equal(length(plain$verification_events), 2L)
    expect_identical(plain$verification_events[[1]], td)
    expect_identical(plain$verification_events[[2]]$room_id, room)

    # Real Olm-encrypted to-device verification, not just the cleartext branch.
    olm <- out$sessions$olm[[bk$curve25519]]
    payload <- list(sender = "@alice:example.org", recipient = "@bob:example.org",
        keys = list(ed25519 = ak$ed25519), recipient_keys = list(ed25519 = bk$ed25519),
        type = td$type, content = td$content)
    olm_response <- function(sender = "@alice:example.org") {
        msg <- mx.crypto::mxc_olm_encrypt(olm, charToRaw(mx.api::mx_canonical_json(payload)))
        list(to_device = list(events = list(list(type = "m.room.encrypted", sender = sender,
            content = list(algorithm = "m.olm.v1.curve25519-aes-sha2",
                sender_key = ak$curve25519, ciphertext = setNames(list(msg), bk$curve25519))))))
    }
    received <- mx_crypto_process_sync(b, res$sessions, olm_response(),
        bk$curve25519, "@bob:example.org", devices, "B")
    expect_equal(length(received$verification_events), 1L)
    expect_identical(received$verification_events[[1]]$type, td$type)
    received <- mx_crypto_process_sync(b, res$sessions, olm_response("@mallory:example.org"),
        bk$curve25519, "@bob:example.org", devices, "B")
    expect_equal(length(received$verification_events), 0L)

    # Verification transport saves ratchets before HTTP and retries the same
    # encrypted bytes and ids, leaving unsent key delivery unmarked on disk.
    store <- tempfile("sas-send-")
    on.exit(unlink(store, recursive = TRUE), add = TRUE)
    ctx <- new.env()
    ctx$client <- list(server = "https://example.invalid", token = "fixture",
        user_id = "@alice:example.org", device_id = "A")
    ctx$store_dir <- store
    ctx$account <- a
    ctx$sessions <- mx_crypto_sessions_new()
    ctx$pending <- list()
    sequence <- character()
    sent <- list()
    fail <- TRUE
    original <- list(recipients = mx.client:::verification_recipients,
        device = mx.api::mx_send_to_device, event = mx.api::mx_send_event)
    on.exit({
        assignInNamespace("verification_recipients", original$recipients, "mx.client")
        assignInNamespace("mx_send_to_device", original$device, "mx.api")
        assignInNamespace("mx_send_event", original$event, "mx.api")
    }, add = TRUE)
    assignInNamespace("verification_recipients", function(...) list(recipient), "mx.client")
    assignInNamespace("mx_send_to_device", function(session, event_type, messages, txn_id) {
        sequence <<- c(sequence, "key")
        disk <- mx_crypto_sessions_load(store)
        expect_equal(length(disk$olm), 1L)
        expect_equal(length(disk$megolm_out[[room]]$shared), 0L)
        sent[[length(sent) + 1L]] <<- list(id = txn_id, messages = messages)
        if (fail) stop("fixture send failure")
        list()
    }, "mx.api")
    assignInNamespace("mx_send_event", function(session, room_id, event_type, content, txn_id) {
        sequence <<- c(sequence, "room")
        expect_identical(event_type, "m.room.encrypted")
        expect_identical(txn_id, "fixed-id")
        expect_identical(content$`m.relates_to`, relation)
        "$sent"
    }, "mx.api")
    envelope <- list(id = "fixed-id", user_id = "@bob:example.org", device_id = "B",
        room_id = room, type = "m.key.verification.ready", content = content)
    expect_error(mx.client:::verification_send(ctx, envelope, TRUE), "fixture send failure")
    expect_identical(sequence, "key")
    expect_equal(length(ctx$pending), 1L)
    expect_equal(length(mx_crypto_sessions_load(store)$megolm_out[[room]]$shared), 0L)
    fail <- FALSE
    mx.client:::verification_send(ctx, envelope, TRUE)
    expect_identical(sequence, c("key", "key", "room"))
    expect_identical(sent[[1]], sent[[2]])
    expect_equal(length(ctx$pending), 0L)
    expect_identical(mx_crypto_sessions_load(store)$megolm_out[[room]]$shared, bk$curve25519)
})
