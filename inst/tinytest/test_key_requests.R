library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    utils::packageVersion("mx.crypto") < "0.2.1.1") {
    exit_file("mx.crypto >= 0.2.1.1 not available (needs a Rust toolchain)")
}
library(mx.client)

local({
uid <- "@bob:example.org"
device_id <- "BOB-NEW"
room_id <- "!history:example.org"

# Alice has an existing outbound session, but Bob's new device missed the
# original m.room_key share.
alice <- mx.crypto::mxc_account_new()
alice_keys <- mx.crypto::mxc_account_identity_keys(alice)
outbound <- mx.crypto::mxc_megolm_outbound_new()
outbound_info <- mx.crypto::mxc_megolm_outbound_info(outbound)
encrypted <- mx_crypto_encrypt_event(
    outbound, list(msgtype = "m.text", body = "recover me"), room_id,
    alice_keys$curve25519, "ALICE")

bob <- mx.crypto::mxc_account_new()
bob_keys <- mx.crypto::mxc_account_identity_keys(bob)
timeline <- list(
    to_device = list(events = list()),
    rooms = list(join = stats::setNames(list(list(timeline = list(events =
        list(list(type = "m.room.encrypted", event_id = "$missing",
                  sender = "@alice:example.org", content = encrypted))))),
        room_id))
)

missing <- mx_crypto_process_sync(
    bob, mx_crypto_sessions_new(), timeline, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id)
expect_equal(length(missing$events), 0L)
expect_equal(length(missing$key_requests), 1L)
request <- missing$key_requests[[1]]
expect_equal(request$user_id, uid) # requests go to our own other devices
expect_equal(request$content$action, "request")
expect_equal(request$content$requesting_device_id, device_id)
expect_equal(request$content$body$room_id, room_id)
expect_equal(request$content$body$session_id, outbound_info$session_id)
expect_equal(request$content$body$sender_key, alice_keys$curve25519)
expect_true(nzchar(request$content$request_id))
expect_true(grepl("^[0-9]+[.][0-9]{9}$", request$content$request_id))
expect_identical(request$content$request_id, request$request_id)
expect_false(request$sent)

# Outstanding unsent requests survive restart and retry with the same id.
store <- tempfile("key-request-store-")
on.exit(unlink(store, recursive = TRUE), add = TRUE)
mx_crypto_sessions_save(missing$sessions, store)
persisted <- mx_crypto_sessions_load(store)
expect_equal(length(persisted$key_requests), 1L)
retry <- mx_crypto_process_sync(
    bob, persisted, timeline, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id)
expect_equal(length(retry$key_requests), 1L)
expect_equal(retry$key_requests[[1]]$request_id, request$request_id)
sent_sessions <- mx_crypto_mark_key_requests_sent(
    retry$sessions, retry$key_requests)
expect_true(sent_sessions$key_requests[[1]]$sent)
mx_crypto_sessions_save(sent_sessions, store)
persisted_sent <- mx_crypto_sessions_load(store)
again <- mx_crypto_process_sync(
    bob, persisted_sent, timeline, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id)
expect_equal(length(again$key_requests), 0L)
expect_equal(again$sessions$key_requests[[1]]$request_id,
             request$request_id)

# A cross-signed device belonging to Bob forwards the exported session over
# Olm. The pending-request match and imported session-id check happen before
# the key is installed.
other <- mx.crypto::mxc_account_new()
other_keys <- mx.crypto::mxc_account_identity_keys(other)
mx.crypto::mxc_account_generate_one_time_keys(bob, 1L)
bob_otk <- mx.crypto::mxc_account_one_time_keys(bob)[[1]]
olm <- mx.crypto::mxc_olm_create_outbound(
    other, bob_keys$curve25519, bob_otk)
original_inbound <- mx.crypto::mxc_megolm_inbound_new(
    outbound_info$session_key)
forwarded_key <- mx.crypto::mxc_megolm_inbound_export(original_inbound)
forwarded_plain <- list(
    type = "m.forwarded_room_key",
    content = list(
        algorithm = "m.megolm.v1.aes-sha2",
        room_id = room_id,
        session_id = outbound_info$session_id,
        session_key = forwarded_key,
        sender_key = alice_keys$curve25519,
        sender_claimed_ed25519_key = alice_keys$ed25519,
        forwarding_curve25519_key_chain = list()),
    sender = uid,
    recipient = uid,
    recipient_keys = list(ed25519 = bob_keys$ed25519),
    keys = list(ed25519 = other_keys$ed25519))
olm_ciphertext <- mx.crypto::mxc_olm_encrypt(
    olm, charToRaw(mx.api::mx_canonical_json(forwarded_plain)))
to_device <- list(
    type = "m.room.encrypted", sender = uid,
    content = list(
        algorithm = "m.olm.v1.curve25519-aes-sha2",
        sender_key = other_keys$curve25519,
        ciphertext = stats::setNames(
            list(list(type = olm_ciphertext$type, body = olm_ciphertext$body)),
            bob_keys$curve25519)))
recovery_sync <- timeline
recovery_sync$to_device$events <- list(to_device)
devices <- list(
    list(user_id = uid, device_id = "BOB-OLD",
         curve25519 = other_keys$curve25519,
         ed25519 = other_keys$ed25519, cross_signed = TRUE),
    list(user_id = "@alice:example.org", device_id = "ALICE",
         curve25519 = alice_keys$curve25519,
         ed25519 = alice_keys$ed25519, cross_signed = TRUE))
recovered <- mx_crypto_process_sync(
    bob, again$sessions, recovery_sync, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id, devices = devices)
expect_equal(length(recovered$events), 1L)
expect_equal(recovered$events[[1]]$body, "recover me")
expect_false(recovered$events[[1]]$sender_verified)
expect_equal(length(recovered$key_request_cancellations), 1L)
expect_equal(recovered$key_request_cancellations[[1]]$content$action,
             "request_cancellation")
expect_equal(recovered$key_request_cancellations[[1]]$content$request_id,
             request$request_id)
expect_equal(length(recovered$sessions$key_requests), 0L)

# Plaintext request events are surfaced for a separate, policy-aware sharing
# layer; processing sync never auto-forwards history.
incoming_sync <- list(
    to_device = list(events = list(
        list(
        type = "m.room_key_request", sender = uid,
        content = list(action = "request", request_id = "req-1",
                       requesting_device_id = "BOB-OLD",
                       body = request$content$body)),
        list(type = "m.room_key_request", sender = uid,
             content = list(action = "request", request_id = "req-self",
                            requesting_device_id = device_id,
                            body = request$content$body)))),
    rooms = list(join = list()))
incoming <- mx_crypto_process_sync(
    bob, recovered$sessions, incoming_sync, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id, devices = devices)

# New outbound Megolm sessions retain a local inbound copy, so own echoes
# decrypt without requesting their key from this same device.
self_out <- mx_crypto_encrypt_for_devices(
    bob, mx_crypto_sessions_new(), room_id,
    list(msgtype = "m.text", body = "own echo"),
    bob_keys$curve25519, device_id, sender_user_id = uid)
self_timeline <- list(
    to_device = list(events = list()),
    rooms = list(join = stats::setNames(list(list(timeline = list(events =
        list(list(type = "m.room.encrypted", event_id = "$self",
                  sender = uid, content = self_out$event))))), room_id)))
self_result <- mx_crypto_process_sync(
    bob, self_out$sessions, self_timeline, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id)
expect_equal(length(self_result$events), 1L)
expect_equal(self_result$events[[1]]$body, "own echo")
expect_true(self_result$events[[1]]$sender_verified)
expect_equal(length(self_result$key_requests), 0L)

# A legacy store may have the outbound session but no local inbound mirror;
# its echo is skipped without generating a request to ourselves.
legacy_self <- self_out$sessions
legacy_self$megolm_in <- list()
legacy_result <- mx_crypto_process_sync(
    bob, legacy_self, self_timeline, bob_keys$curve25519,
    self_id = uid, self_device_id = device_id)
expect_equal(length(legacy_result$events), 0L)
expect_equal(length(legacy_result$key_requests), 0L)
expect_equal(length(incoming$incoming_key_requests), 1L)
expect_equal(incoming$incoming_key_requests[[1]]$content$request_id, "req-1")

# Transport uses an unencrypted wildcard to-device event for this user.
local({
    sent <- NULL
    old_session <- mx.client::mx_client_session
    old_send <- mx.api::mx_send_to_device
    assignInNamespace("mx_client_session", function(client, ...) list(ok = TRUE),
                      ns = "mx.client")
    assignInNamespace("mx_send_to_device", function(session, event_type,
                                                     messages, txn_id = NULL) {
        sent <<- list(type = event_type, messages = messages)
        list()
    }, ns = "mx.api")
    on.exit({
        assignInNamespace("mx_client_session", old_session, ns = "mx.client")
        assignInNamespace("mx_send_to_device", old_send, ns = "mx.api")
    })
    mx_crypto_send_key_requests(list(), list(request))
    expect_equal(sent$type, "m.room_key_request")
    expect_equal(sent$messages[[uid]][["*"]]$request_id,
                 request$request_id)
})
})
