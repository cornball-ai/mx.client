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
alice_ed <- mx.crypto::mxc_account_identity_keys(alice)$ed25519
bob_ed <- mx.crypto::mxc_account_identity_keys(bob)$ed25519
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
                    curve25519 = bob_curve, ed25519 = bob_ed, otk = bob_otk))
out1 <- mx_crypto_encrypt_for_devices(
    alice, a_sess, ROOM, list(msgtype = "m.text", body = "first secret"),
    alice_curve, "ALICEDEV", recipients = recips,
    sender_user_id = "@alice:example.org")
a_sess <- out1$sessions
expect_equal(length(out1$to_device), 1L)         # key shared with Bob

res1 <- mx_crypto_process_sync(bob, b_sess, bob_sync(out1, "$1"),
                               bob_curve, self_id = "@bob:example.org")
b_sess <- res1$sessions
expect_equal(length(res1$events), 1L)
expect_equal(res1$events[[1]]$body, "first secret")   # decrypted
expect_false(res1$events[[1]]$is_self)
expect_true(res1$events[[1]]$sender_verified)         # attested over Olm

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
    alice_curve, "ALICEDEV", recipients = recips,
    sender_user_id = "@alice:example.org")
a_sess <- out2$sessions
expect_equal(length(out2$to_device), 0L)              # already shared

res2 <- mx_crypto_process_sync(bob, b_sess,
                               bob_sync(out2, "$2", with_to_device = FALSE),
                               bob_curve, self_id = "@bob:example.org")
expect_equal(length(res2$events), 1L)
expect_equal(res2$events[[1]]$body, "second secret")  # decrypted from reloaded state
expect_true(res2$events[[1]]$sender_verified)         # survives the store round-trip

# ---- a forged envelope sender is dropped, not reported ----
# The server rewrites `sender` on the timeline event. The Megolm session
# was shared by Alice over Olm, so the lie is detectable.
forged <- bob_sync(out2, "$3", with_to_device = FALSE)
forged$rooms$join[[ROOM]]$timeline$events[[1]]$sender <- "@mallory:example.org"
res3 <- suppressWarnings(
    mx_crypto_process_sync(bob, b_sess, forged, bob_curve,
                           self_id = "@bob:example.org"))
expect_equal(length(res3$events), 0L)

# ---- an Olm payload addressed to someone else is dropped ----
carol <- mx.crypto::mxc_account_new()
carol_curve <- mx.crypto::mxc_account_identity_keys(carol)$curve25519
carol_ed <- mx.crypto::mxc_account_identity_keys(carol)$ed25519
mx.crypto::mxc_account_generate_one_time_keys(bob, 2L)
bob_otk2 <- mx.crypto::mxc_account_one_time_keys(bob)[[2]]
# Alice shares a key naming Carol as recipient, but sends it to Bob.
misaddressed <- mx_crypto_encrypt_for_devices(
    alice, mx_crypto_sessions_new(), "!other:example.org",
    list(msgtype = "m.text", body = "not for bob"), alice_curve, "ALICEDEV",
    recipients = list(list(user_id = "@carol:example.org",
                           device_id = "CAROLDEV", curve25519 = bob_curve,
                           ed25519 = carol_ed, otk = bob_otk2)),
    sender_user_id = "@alice:example.org")
res4 <- suppressWarnings(
    mx_crypto_process_sync(bob, mx_crypto_sessions_new(),
                           bob_sync(misaddressed, "$4"), bob_curve,
                           self_id = "@bob:example.org"))
expect_equal(length(res4$sessions$megolm_in), 0L)     # key not installed

# ---- a legacy store (bare pickle) still loads ----
legacy_store <- file.path(tempfile(), "legacy")
dir.create(legacy_store, recursive = TRUE)
mx_crypto_sessions_save(b_sess, legacy_store)
raw <- jsonlite::fromJSON(paste(readLines(
    file.path(legacy_store, "sessions.json"), warn = FALSE), collapse = "\n"),
    simplifyVector = FALSE)
raw$megolm_in <- lapply(raw$megolm_in, function(e) e$session)  # old shape
writeLines(jsonlite::toJSON(raw, auto_unbox = TRUE),
           file.path(legacy_store, "sessions.json"))
reloaded <- mx_crypto_sessions_load(legacy_store)
expect_equal(length(reloaded$megolm_in), length(b_sess$megolm_in))
res5 <- mx_crypto_process_sync(bob, reloaded,
                               bob_sync(out2, "$5", with_to_device = FALSE),
                               bob_curve, self_id = "@bob:example.org")
expect_equal(length(res5$events), 1L)                 # history still decrypts
expect_false(res5$events[[1]]$sender_verified)        # but carries no attestation
