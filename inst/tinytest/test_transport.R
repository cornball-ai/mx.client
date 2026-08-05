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

# ---- A partial response is not an empty one ----
# /keys/query and /keys/claim both answer 200 with a `failures` map and
# whatever they did manage. Reading only the successful half makes an
# unreachable homeserver look like a user with no devices, which on the
# send path means encrypting to nobody and reporting success.
rf <- mx.client:::mx_crypto_report_failures
expect_false(rf(NULL, "/keys/query"))
expect_false(rf(list(), "/keys/query"))
expect_warning(rf(list(`ex.org` = list()), "/keys/query"),
               "could not reach ex.org")
expect_error(rf(list(`ex.org` = list()), "/keys/query", strict = TRUE),
             "could not reach ex.org")
# Every unreachable server is named, not just the first.
expect_error(rf(list(a = list(), b = list()), "/keys/claim", strict = TRUE),
             "a, b")
# Both call sites take the flag, so the send path can ask for strict
# while the decrypt path stays best-effort.
expect_true("strict" %in% names(formals(mx_crypto_known_devices)))
expect_true("strict" %in% names(formals(mx_crypto_claim_otks)))

# ---- Device ids are scoped to a user ----
# mx_send_encrypted() filters out its own device. Comparing device_id
# alone dropped every other account whose device happened to share the
# name: two bots both called BOT, and the only recipient disappears while
# the send still returns an event id.
local({
    me <- list(user_id = "@alice:example.org", device_id = "BOT",
               server = "https://ex.invalid", token = "t")
    bob <- mx.crypto::mxc_account_new()
    bob_idk <- mx.crypto::mxc_account_identity_keys(bob)
    bob_dk <- mx_crypto_device_keys(bob, "@bob:example.org", "BOT")
    alice_dk <- mx_crypto_device_keys(alice, "@alice:example.org", "BOT")
    resp <- list(device_keys = list(
        `@bob:example.org` = stats::setNames(list(bob_dk), "BOT"),
        `@alice:example.org` = stats::setNames(list(alice_dk), "BOT")))

    seen <- NULL
    o1 <- mx.api::mx_keys_query
    assignInNamespace("mx_keys_query", function(...) resp, ns = "mx.api")
    o2 <- mx.api::mx_keys_claim
    assignInNamespace("mx_keys_claim", function(session, one_time_keys) {
        seen <<- names(one_time_keys)
        list(one_time_keys = list())
    }, ns = "mx.api")
    on.exit({
        assignInNamespace("mx_keys_query", o1, ns = "mx.api")
        assignInNamespace("mx_keys_claim", o2, ns = "mx.api")
    })

    acct <- mx.crypto::mxc_account_new()
    store <- tempfile("sendstore")
    # Bob's BOT survives the self-filter, so a key is claimed for him and
    # the send gets that far. Alice's own BOT is the only one dropped.
    expect_error(mx_send_encrypted(me, acct, mx_crypto_sessions_new(),
                                   "!r:ex", list(msgtype = "m.text",
                                                 body = "hi"), store,
                                   member_ids = c("@bob:example.org",
                                                  "@alice:example.org")),
                 "was skipped")
    expect_identical(seen, "@bob:example.org")
    unlink(store, recursive = TRUE)
})

# ---- Every device skipped is not a room of one ----
# Skipping some devices is the documented policy. Skipping all of them
# means the room key reaches nobody, and posting the event anyway hands
# the caller an event id for a message every recipient will fail to
# decrypt.
local({
    me <- list(user_id = "@alice:example.org", device_id = "ALICEDEV",
               server = "https://ex.invalid", token = "t")
    bob <- mx.crypto::mxc_account_new()
    bob_dk <- mx_crypto_device_keys(bob, "@bob:example.org", "BOBDEV")
    posted <- 0L
    o1 <- mx.api::mx_keys_query
    assignInNamespace("mx_keys_query", function(...) list(device_keys = list(
        `@bob:example.org` = stats::setNames(list(bob_dk), "BOBDEV"))),
        ns = "mx.api")
    o2 <- mx.api::mx_keys_claim
    # No one-time keys come back, so Bob's device is skipped and nothing
    # is left.
    assignInNamespace("mx_keys_claim", function(...) list(one_time_keys = list()),
                      ns = "mx.api")
    o3 <- mx.api::mx_send_event
    assignInNamespace("mx_send_event", function(...) { posted <<- posted + 1L
                                                       "$e" }, ns = "mx.api")
    on.exit({
        assignInNamespace("mx_keys_query", o1, ns = "mx.api")
        assignInNamespace("mx_keys_claim", o2, ns = "mx.api")
        assignInNamespace("mx_send_event", o3, ns = "mx.api")
    })
    acct <- mx.crypto::mxc_account_new()
    store <- tempfile("sendstore2")
    expect_error(mx_send_encrypted(me, acct, mx_crypto_sessions_new(),
                                   "!r:ex", list(msgtype = "m.text",
                                                 body = "hi"), store,
                                   member_ids = "@bob:example.org"),
                 "none usable")
    # And nothing was posted.
    expect_identical(posted, 0L)
    unlink(store, recursive = TRUE)
})

# A room whose only member is us is a room of one, not a failure: no
# other devices were found, so there is nothing to have skipped.
local({
    me <- list(user_id = "@alice:example.org", device_id = "ALICEDEV",
               server = "https://ex.invalid", token = "t")
    alice_dk <- mx_crypto_device_keys(alice, "@alice:example.org", "ALICEDEV")
    posted <- 0L
    o1 <- mx.api::mx_keys_query
    assignInNamespace("mx_keys_query", function(...) list(device_keys = list(
        `@alice:example.org` = stats::setNames(list(alice_dk), "ALICEDEV"))),
        ns = "mx.api")
    o2 <- mx.api::mx_send_event
    assignInNamespace("mx_send_event", function(...) { posted <<- posted + 1L
                                                       "$solo" }, ns = "mx.api")
    on.exit({
        assignInNamespace("mx_keys_query", o1, ns = "mx.api")
        assignInNamespace("mx_send_event", o2, ns = "mx.api")
    })
    acct <- mx.crypto::mxc_account_new()
    store <- tempfile("sendstore3")
    res <- mx_send_encrypted(me, acct, mx_crypto_sessions_new(), "!r:ex",
                             list(msgtype = "m.text", body = "note to self"),
                             store, member_ids = "@alice:example.org")
    expect_identical(res$event_id, "$solo")
    expect_identical(posted, 1L)
    unlink(store, recursive = TRUE)
})

# A /keys/query that could not reach Bob's server aborts the send rather
# than treating him as a user with no devices.
local({
    me <- list(user_id = "@alice:example.org", device_id = "ALICEDEV",
               server = "https://ex.invalid", token = "t")
    posted <- 0L
    o1 <- mx.api::mx_keys_query
    assignInNamespace("mx_keys_query", function(...) list(
        device_keys = list(),
        failures = list(`example.org` = list(errcode = "M_UNKNOWN"))),
        ns = "mx.api")
    o2 <- mx.api::mx_send_event
    assignInNamespace("mx_send_event", function(...) { posted <<- posted + 1L
                                                       "$e" }, ns = "mx.api")
    on.exit({
        assignInNamespace("mx_keys_query", o1, ns = "mx.api")
        assignInNamespace("mx_send_event", o2, ns = "mx.api")
    })
    acct <- mx.crypto::mxc_account_new()
    store <- tempfile("sendstore4")
    expect_error(mx_send_encrypted(me, acct, mx_crypto_sessions_new(),
                                   "!r:ex", list(msgtype = "m.text",
                                                 body = "hi"), store,
                                   member_ids = "@bob:example.org"),
                 "could not reach example.org")
    expect_identical(posted, 0L)
    unlink(store, recursive = TRUE)
})
