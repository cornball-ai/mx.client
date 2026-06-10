# Two-party E2EE messaging loopback: Alice encrypts for an encrypted
# room, Bob recovers the key from the to-device payload and decrypts the
# timeline event -- entirely through mx.client's send/sync integration,
# with a persistence round-trip and an established-session second message.

library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE)) {
    exit_file("mx.crypto not available (needs a Rust toolchain)")
}
library(mx.client)

ROOM <- "!secret:example.org"

alice <- mx.crypto::mxc_account_new()
bob <- mx.crypto::mxc_account_new()
alice_curve <- mx.crypto::mxc_account_identity_keys(alice)$curve25519
bob_curve <- mx.crypto::mxc_account_identity_keys(bob)$curve25519
mx.crypto::mxc_account_generate_one_time_keys(bob, 2L)
bob_otk <- mx.crypto::mxc_account_one_time_keys(bob)[[1]]

a_store <- file.path(tempfile(), "a")
b_store <- file.path(tempfile(), "b")
a_sess <- mx_crypto_sessions_new()
b_sess <- mx_crypto_sessions_new()

# Helper: assemble a sync response for Bob from Alice's send output.
bob_sync <- function(out, event_id, with_to_device = TRUE) {
    td <- if (with_to_device && length(out$to_device)) {
        lapply(out$to_device, function(p) {
            list(type = "m.room.encrypted", sender = "@alice:example.org",
                 content = p$content)
        })
    } else list()
    list(
        to_device = list(events = td),
        rooms = list(join = stats::setNames(list(list(timeline = list(
            events = list(list(type = "m.room.encrypted",
                               event_id = event_id, sender = "@alice:example.org",
                               content = out$event))))), ROOM))
    )
}

# ---- message 1: fresh session (prekey Olm + Megolm key share) ----
recips <- list(list(user_id = "@bob:example.org", device_id = "BOBDEV",
                    curve25519 = bob_curve, otk = bob_otk))
out1 <- mx_crypto_encrypt_for_devices(
    alice, a_sess, ROOM, list(msgtype = "m.text", body = "first secret"),
    alice_curve, "ALICEDEV", recipients = recips)
a_sess <- out1$sessions
expect_equal(length(out1$to_device), 1L)         # key shared with Bob

res1 <- mx_crypto_process_sync(bob, b_sess, bob_sync(out1, "$1"),
                               bob_curve, self_id = "@bob:example.org")
b_sess <- res1$sessions
expect_equal(length(res1$events), 1L)
expect_equal(res1$events[[1]]$body, "first secret")   # decrypted
expect_false(res1$events[[1]]$is_self)

# ---- persist both sides, reload from disk ----
mx_crypto_sessions_save(a_sess, a_store)
mx_crypto_sessions_save(b_sess, b_store)
a_sess <- mx_crypto_sessions_load(a_store)
b_sess <- mx_crypto_sessions_load(b_store)
expect_true(ROOM %in% names(a_sess$megolm_out))       # outbound survived
expect_true(bob_curve %in% a_sess$megolm_out[[ROOM]]$shared)
expect_equal(length(b_sess$megolm_in), 1L)            # inbound survived

# ---- message 2: established session, no re-share, decrypt from store ----
out2 <- mx_crypto_encrypt_for_devices(
    alice, a_sess, ROOM, list(msgtype = "m.text", body = "second secret"),
    alice_curve, "ALICEDEV", recipients = recips)
a_sess <- out2$sessions
expect_equal(length(out2$to_device), 0L)              # already shared

res2 <- mx_crypto_process_sync(bob, b_sess,
                               bob_sync(out2, "$2", with_to_device = FALSE),
                               bob_curve, self_id = "@bob:example.org")
expect_equal(length(res2$events), 1L)
expect_equal(res2$events[[1]]$body, "second secret")  # decrypted from reloaded state
