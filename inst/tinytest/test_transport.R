# Homeserver key verification. These exercise the pure halves of the
# /keys/query and /keys/claim handling against fixture responses, so the
# security-relevant logic is covered without a live homeserver -- which is
# exactly the gap that let the unverified paths ship in the first place.

library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE)) {
    exit_file("mx.crypto not available (needs a Rust toolchain)")
}
library(mx.client)

UID <- "@alice:example.org"
DEV <- "ALICEDEV"

alice <- mx.crypto::mxc_account_new()
mallory <- mx.crypto::mxc_account_new()
alice_idk <- mx.crypto::mxc_account_identity_keys(alice)
mallory_idk <- mx.crypto::mxc_account_identity_keys(mallory)

dk <- mx_crypto_device_keys(alice, UID, DEV)
good_map <- stats::setNames(list(stats::setNames(list(dk), DEV)), UID)

# ---- a well-formed device verifies and yields its real keys ----
devs <- mx.client:::mx_crypto_verify_device_map(good_map)
expect_equal(length(devs), 1L)
expect_equal(devs[[1]]$user_id, UID)
expect_equal(devs[[1]]$device_id, DEV)
expect_equal(devs[[1]]$curve25519, alice_idk$curve25519)
expect_equal(devs[[1]]$ed25519, alice_idk$ed25519)

# ---- a substituted curve25519 key is rejected ----
# This is the attack the whole exercise exists to stop: the homeserver
# swaps in a key it holds the private half of and reads the room.
swapped <- good_map
swapped[[UID]][[DEV]]$keys[[paste0("curve25519:", DEV)]] <-
    mallory_idk$curve25519
expect_warning(res <- mx.client:::mx_crypto_verify_device_map(swapped))
expect_equal(length(res), 0L)

# ---- a stripped signatures block is rejected ----
unsigned <- good_map
unsigned[[UID]][[DEV]]$signatures <- NULL
expect_warning(res <- mx.client:::mx_crypto_verify_device_map(unsigned))
expect_equal(length(res), 0L)

# ---- a device reattributed to another user is rejected ----
reattributed <- stats::setNames(list(stats::setNames(list(dk), DEV)),
                                "@mallory:example.org")
expect_warning(res <- mx.client:::mx_crypto_verify_device_map(reattributed))
expect_equal(length(res), 0L)

# ---- a device reattributed to another device id is rejected ----
renamed <- stats::setNames(list(stats::setNames(list(dk), "OTHERDEV")), UID)
expect_warning(res <- mx.client:::mx_crypto_verify_device_map(renamed))
expect_equal(length(res), 0L)

# ---- one bad device does not take the good ones with it ----
bob <- mx.crypto::mxc_account_new()
bob_dk <- mx_crypto_device_keys(bob, "@bob:example.org", "BOBDEV")
mixed <- c(good_map,
           stats::setNames(list(stats::setNames(list(bob_dk), "BOBDEV")),
                           "@bob:example.org"))
mixed[[UID]][[DEV]]$signatures <- NULL          # alice's device is broken
expect_warning(res <- mx.client:::mx_crypto_verify_device_map(mixed))
expect_equal(length(res), 1L)                   # bob still usable
expect_equal(res[[1]]$user_id, "@bob:example.org")

# ---- empty / absent map is not an error ----
expect_equal(length(mx.client:::mx_crypto_verify_device_map(NULL)), 0L)
expect_equal(length(mx.client:::mx_crypto_verify_device_map(list())), 0L)

# ---- one-time keys: a correctly signed key verifies ----
mx.crypto::mxc_account_generate_one_time_keys(alice, 1L)
otks <- mx.crypto::mxc_account_one_time_keys(alice)
kid <- names(otks)[[1]]
signed <- mx.client:::mx_crypto_sign_otk(alice, otks[[kid]], UID, DEV)
claimed <- stats::setNames(
    list(stats::setNames(
        list(stats::setNames(list(signed), paste0("signed_curve25519:", kid))),
        DEV)),
    UID)

device <- list(user_id = UID, device_id = DEV,
               curve25519 = alice_idk$curve25519, ed25519 = alice_idk$ed25519)
res <- mx.client:::mx_crypto_verify_claimed_otks(list(device), claimed)
expect_equal(res[[1]]$otk, otks[[kid]])

# ---- a one-time key signed by the wrong device is rejected ----
forged <- mx.client:::mx_crypto_sign_otk(mallory, otks[[kid]], UID, DEV)
forged_claimed <- stats::setNames(
    list(stats::setNames(
        list(stats::setNames(list(forged), paste0("signed_curve25519:", kid))),
        DEV)),
    UID)
expect_warning(
    res <- mx.client:::mx_crypto_verify_claimed_otks(list(device),
                                                     forged_claimed))
expect_null(res[[1]]$otk)

# ---- a device with no verified ed25519 cannot have its OTK checked ----
no_ed <- list(user_id = UID, device_id = DEV,
              curve25519 = alice_idk$curve25519, ed25519 = NULL)
expect_warning(
    res <- mx.client:::mx_crypto_verify_claimed_otks(list(no_ed), claimed))
expect_null(res[[1]]$otk)

# ---- a device the server returned nothing for is passed through ----
res <- mx.client:::mx_crypto_verify_claimed_otks(list(device), list())
expect_equal(length(res), 1L)
expect_null(res[[1]]$otk)
