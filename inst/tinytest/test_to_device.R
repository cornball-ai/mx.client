# Olm to-device events of arbitrary type: Alice encrypts one for Bob's
# device, Bob's sync processing decrypts it and hands it back in
# `to_device`; the shape of the payload and the sender checks.

library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE)) {
    exit_file("mx.crypto not available (needs a Rust toolchain)")
}
library(mx.client)

alice <- mx.crypto::mxc_account_new()
bob <- mx.crypto::mxc_account_new()
alice_keys <- mx.crypto::mxc_account_identity_keys(alice)
bob_keys <- mx.crypto::mxc_account_identity_keys(bob)
mx.crypto::mxc_account_generate_one_time_keys(bob, 2L)
bob_otk <- mx.crypto::mxc_account_one_time_keys(bob)[[1]]

bob_device <- list(user_id = "@bob:example.org", device_id = "BOBDEV",
                   curve25519 = bob_keys$curve25519,
                   ed25519 = bob_keys$ed25519, otk = bob_otk)

content <- list(keys = list(index = 3L, key = "AAECAwQFBgcICQoLDA0ODw=="),
                member = list(id = "@alice:example.org:ALICEDEV",
                              claimed_device_id = "ALICEDEV"),
                room_id = "!call:example.org")

# Encrypt: one payload per recipient, Olm session opened and retained
a_sess <- mx_crypto_sessions_new()
out <- mx_crypto_encrypt_to_device(alice, a_sess,
                                   "io.element.call.encryption_keys", content,
                                   recipients = list(bob_device),
                                   sender_user_id = "@alice:example.org")
expect_equal(length(out$to_device), 1L)
expect_identical(out$to_device[[1]]$user_id, "@bob:example.org")
expect_identical(out$to_device[[1]]$device_id, "BOBDEV")
payload <- out$to_device[[1]]$content
expect_identical(payload$algorithm, "m.olm.v1.curve25519-aes-sha2")
expect_identical(payload$sender_key, alice_keys$curve25519)
expect_identical(names(payload$ciphertext), bob_keys$curve25519)
expect_identical(payload$ciphertext[[1]]$type, 0L)  # prekey message
expect_true(!is.null(out$sessions$olm[[bob_keys$curve25519]]))

# No recipients: nothing to send, no error
expect_equal(length(mx_crypto_encrypt_to_device(alice, a_sess, "x", list(),
                                                list(), "@alice:example.org")$to_device),
             0L)

# A recipient without verified keys is refused
expect_error(mx_crypto_encrypt_to_device(alice, a_sess, "x", list(),
    list(list(user_id = "@c:ex", device_id = "C", curve25519 = "k")), "@a:ex"),
    "no verified keys")

# Decrypt on Bob's side through process_sync: the event comes back in
# to_device with its type, content and sender
b_sess <- mx_crypto_sessions_new()
sync <- list(to_device = list(events = list(list(
    type = "m.room.encrypted", sender = "@alice:example.org",
    content = payload))), rooms = list(join = list()))
res <- mx_crypto_process_sync(bob, b_sess, sync, bob_keys$curve25519,
                              self_id = "@bob:example.org",
                              self_device_id = "BOBDEV")
expect_equal(length(res$to_device), 1L)
ev <- res$to_device[[1]]
expect_identical(ev$type, "io.element.call.encryption_keys")
expect_identical(ev$sender, "@alice:example.org")
expect_identical(ev$content$keys$key, content$keys$key)
expect_identical(ev$content$member$claimed_device_id, "ALICEDEV")
expect_false(ev$sender_bound)  # no device list given, so a claim only
expect_equal(length(res$events), 0L)
expect_equal(length(res$verification_events), 0L)

# With Alice's device known, the sender is bound
alice_device <- list(user_id = "@alice:example.org", device_id = "ALICEDEV",
                     curve25519 = alice_keys$curve25519,
                     ed25519 = alice_keys$ed25519)
out2 <- mx_crypto_encrypt_to_device(alice, out$sessions, "org.example.ping",
                                    list(n = 2L), list(bob_device),
                                    "@alice:example.org")
expect_identical(out2$to_device[[1]]$content$ciphertext[[1]]$type, 0L)
sync2 <- list(to_device = list(events = list(list(
    type = "m.room.encrypted", sender = "@alice:example.org",
    content = out2$to_device[[1]]$content))), rooms = list(join = list()))
res2 <- mx_crypto_process_sync(bob, res$sessions, sync2, bob_keys$curve25519,
                               self_id = "@bob:example.org",
                               devices = list(alice_device),
                               self_device_id = "BOBDEV")
expect_equal(length(res2$to_device), 1L)
expect_true(res2$to_device[[1]]$sender_bound)
expect_identical(res2$to_device[[1]]$content$n, 2L)

# An envelope whose sender disagrees with the plaintext is dropped
out3 <- mx_crypto_encrypt_to_device(alice, out2$sessions, "org.example.ping",
                                    list(n = 3L), list(bob_device),
                                    "@alice:example.org")
sync3 <- list(to_device = list(events = list(list(
    type = "m.room.encrypted", sender = "@mallory:example.org",
    content = out3$to_device[[1]]$content))), rooms = list(join = list()))
res3 <- mx_crypto_process_sync(bob, res2$sessions, sync3, bob_keys$curve25519,
                               self_id = "@bob:example.org",
                               self_device_id = "BOBDEV")
expect_equal(length(res3$to_device), 0L)

# Room keys still take their own path, not the generic one
room_out <- mx_crypto_encrypt_for_devices(alice, out3$sessions, "!r:example.org",
    list(msgtype = "m.text", body = "hi"), alice_keys$curve25519, "ALICEDEV",
    recipients = list(bob_device), sender_user_id = "@alice:example.org")
sync4 <- list(to_device = list(events = list(list(
    type = "m.room.encrypted", sender = "@alice:example.org",
    content = room_out$to_device[[1]]$content))), rooms = list(join = list()))
res4 <- mx_crypto_process_sync(bob, res3$sessions, sync4, bob_keys$curve25519,
                               self_id = "@bob:example.org",
                               self_device_id = "BOBDEV")
expect_equal(length(res4$to_device), 0L)
expect_equal(length(res4$sessions$megolm_in), 1L)

# mx_send_to_device_encrypted: groups payloads by user and device, never
# sends to this device, and persists sessions
local({
    bob2 <- mx.crypto::mxc_account_new()
    mx.crypto::mxc_account_generate_one_time_keys(bob2, 1L)
    bob_otk2 <- mx.crypto::mxc_account_one_time_keys(bob2)[[1]]
    bob2_keys <- mx.crypto::mxc_account_identity_keys(bob2)

    ns <- asNamespace("mx.client")
    sent <- NULL
    orig_claim <- get("mx_crypto_claim_otks", envir = ns)
    assignInNamespace("mx_crypto_claim_otks", function(client, devices, strict) {
        lapply(devices, function(d) { d$otk <- bob_otk2; d })
    }, ns = "mx.client")
    on.exit(assignInNamespace("mx_crypto_claim_otks", orig_claim,
                              ns = "mx.client"), add = TRUE)
    api <- asNamespace("mx.api")
    orig_api_send <- get("mx_send_to_device", envir = api)
    assignInNamespace("mx_send_to_device", function(session, event_type,
                                                    messages, txn_id = NULL) {
        sent <<- list(event_type = event_type, messages = messages)
        list()
    }, ns = "mx.api")
    on.exit(assignInNamespace("mx_send_to_device", orig_api_send, ns = "mx.api"),
            add = TRUE)

    bob2_device <- list(user_id = "@bob:example.org", device_id = "BOBTWO",
                        curve25519 = bob2_keys$curve25519,
                        ed25519 = bob2_keys$ed25519)
    self_device <- list(user_id = "@alice:example.org", device_id = "ALICEDEV",
                        curve25519 = alice_keys$curve25519,
                        ed25519 = alice_keys$ed25519)
    client <- list(server = "https://example.org", token = "t",
                   user_id = "@alice:example.org", device_id = "ALICEDEV")
    store <- tempfile("td-store")
    res <- mx_send_to_device_encrypted(client, alice, room_out$sessions,
                                       "org.example.ping", list(n = 4L),
                                       list(bob_device, bob2_device, self_device),
                                       store_dir = store)
    expect_identical(sent$event_type, "m.room.encrypted")
    expect_identical(names(sent$messages), "@bob:example.org")
    expect_identical(sort(names(sent$messages[["@bob:example.org"]])),
                     c("BOBDEV", "BOBTWO"))
    expect_equal(length(res$sent), 2L)
    expect_true(!is.null(res$sessions$olm[[bob2_keys$curve25519]]))
    expect_true(file.exists(store))
    # Bob's second device opens the session from the prekey message
    msg <- sent$messages[["@bob:example.org"]][["BOBTWO"]]
    syncb <- list(to_device = list(events = list(list(
        type = "m.room.encrypted", sender = "@alice:example.org",
        content = msg))), rooms = list(join = list()))
    rb <- mx_crypto_process_sync(bob2, mx_crypto_sessions_new(), syncb,
                                 bob2_keys$curve25519,
                                 self_id = "@bob:example.org",
                                 self_device_id = "BOBTWO")
    expect_identical(rb$to_device[[1]]$content$n, 4L)
    unlink(store, recursive = TRUE)
})
