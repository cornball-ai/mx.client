# End-to-end encryption loopback: two accounts exchange an encrypted
# room message entirely in-process, through mx.client's own API. No
# homeserver, no network -- just the crypto orchestration.

library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE)) {
    exit_file("mx.crypto not available (needs a Rust toolchain)")
}
library(mx.client)

ROOM <- "!room:example.org"

# ---- accounts (Alice = sender, Bob = recipient) ----
alice <- mx.crypto::mxc_account_new()
bob <- mx.crypto::mxc_account_new()
alice_idk <- mx.crypto::mxc_account_identity_keys(alice)
bob_idk <- mx.crypto::mxc_account_identity_keys(bob)

# Bob publishes a one-time key Alice can claim.
mx.crypto::mxc_account_generate_one_time_keys(bob, 1L)
bob_otk <- mx.crypto::mxc_account_one_time_keys(bob)[[1]]

# ---- device_keys are signed and verifiable ----
dk <- mx_crypto_device_keys(alice, "@alice:example.org", "ALICEDEV")
expect_equal(dk$user_id, "@alice:example.org")
expect_true("curve25519:ALICEDEV" %in% names(dk$keys))
expect_true(!is.null(dk$signatures[["@alice:example.org"]][["ed25519:ALICEDEV"]]))
# the signature verifies against the device's own ed25519 key
verified <- mx.crypto::mxc_verify_device_keys(
    dk, "@alice:example.org", "ALICEDEV",
    required_algorithms = c("m.olm.v1.curve25519-aes-sha2",
                            "m.megolm.v1.aes-sha2"))
expect_true(isTRUE(verified) || is.list(verified))

# ---- Alice establishes an Olm session and a Megolm session ----
olm <- mx.crypto::mxc_olm_create_outbound(
    alice, peer_curve25519 = bob_idk$curve25519, peer_otk = bob_otk)
megolm_out <- mx.crypto::mxc_megolm_outbound_new()

# ---- Alice shares the room key with Bob (to-device payload) ----
td <- mx_crypto_room_key_payload(
    olm, sender_curve25519 = alice_idk$curve25519,
    recipient_curve25519 = bob_idk$curve25519,
    room_id = ROOM, megolm_out = megolm_out)
expect_equal(td$algorithm, "m.olm.v1.curve25519-aes-sha2")
expect_true(bob_idk$curve25519 %in% names(td$ciphertext))

# ---- Bob receives the to-device payload, recovers the room key ----
room_key_ev <- mx_crypto_handle_to_device(bob, bob_idk$curve25519, td)
expect_equal(room_key_ev$type, "m.room_key")
expect_equal(room_key_ev$content$room_id, ROOM)
inbound <- mx_crypto_inbound_session(room_key_ev$content$session_key)

# ---- Alice encrypts a room message; Bob decrypts it ----
enc <- mx_crypto_encrypt_event(
    megolm_out, content = list(msgtype = "m.text", body = "secret hello"),
    room_id = ROOM, sender_curve25519 = alice_idk$curve25519,
    device_id = "ALICEDEV")
expect_equal(enc$algorithm, "m.megolm.v1.aes-sha2")
expect_equal(enc$session_id, room_key_ev$content$session_id)

dec <- mx_crypto_decrypt_event(inbound, enc)
expect_equal(dec$content$body, "secret hello")          # the payoff
expect_equal(dec$room_id, ROOM)

# a non-recipient device gets NULL from the to-device payload
expect_null(mx_crypto_handle_to_device(bob, "wrong-curve-key", td))

# ---- account store: persist, reload, identity stable ----
store <- file.path(tempfile(), "crypto")
acct <- mx_crypto_account(store)                         # mints + saves
id1 <- mx.crypto::mxc_account_identity_keys(acct)$curve25519
acct2 <- mx_crypto_account(store)                        # reloads pickle
id2 <- mx.crypto::mxc_account_identity_keys(acct2)$curve25519
expect_equal(id1, id2)
expect_true(file.exists(file.path(store, "account.pickle")))
expect_equal(length(mx.client:::mx_crypto_key(store)), 32L)  # stable 0600 key
