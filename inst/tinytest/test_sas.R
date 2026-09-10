library(tinytest)
if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    !"mxc_sas_commitment" %in% getNamespaceExports("mx.crypto")) {
    exit_file("mx.crypto SAS primitives are unavailable")
}
library(mx.client)

local({
    make_keys <- function(device) {
        k <- replicate(2, mx.crypto::mxc_signing_key_public(
            mx.crypto::mxc_signing_key_new()))
        setNames(as.list(k), paste0("ed25519:", c(device, k[2])))
    }
    ak <- make_keys("A")
    bk <- make_keys("B")
    pair <- function(room = NULL, same_user = FALSE) {
        alice <- "@alice:example.org"
        bob <- if (same_user) alice else "@bob:example.org"
        list(a = mx_sas_session(alice, "A", ak, bob, "B", bk,
                 "transaction", room, initiator = TRUE, now = 100),
             b = mx_sas_session(bob, "B", bk, alice, "A", ak,
                 "transaction", room, now = 100))
    }
    transfer <- function(from, to, change = identity) {
        pending <- mx_sas_outgoing(from)
        for (item in pending) {
            event <- change(list(type = item$type, content = item$content,
                sender = from$user_id, room_id = item$room_id))
            mx_sas_receive(to, event, now = 101)
            mx_sas_outgoing(from, item$id)
        }
        invisible(length(pending))
    }
    exchange <- function(p) {
        mx_sas_accept(p$b, now = 100)
        for (i in 1:3) {
            transfer(p$b, p$a)
            transfer(p$a, p$b)
        }
        p
    }

    # Real two-party crypto: both transports, either user ordering, and same user.
    for (room in list(NULL, "!room:example.org")) {
        for (same in c(FALSE, TRUE)) {
            p <- exchange(pair(room, same))
            a <- mx_sas_status(p$a)
            b <- mx_sas_status(p$b)
            expect_identical(a$phase, "sas")
            expect_identical(b$phase, "sas")
            expect_identical(a$decimal, b$decimal)
            expect_identical(a$emoji, b$emoji)
            expect_equal(length(a$decimal), 3L)
            expect_equal(length(a$emoji), 7L)
            expect_false(a$local_trust_recorded)
            mx_sas_confirm(p$b, TRUE, now = 101)
            transfer(p$b, p$a)
            expect_true(mx_sas_status(p$a)$peer_mac_valid)
            expect_identical(mx_sas_status(p$a)$phase, "sas")
            # Receiving an authenticated MAC never substitutes for human comparison.
            expect_error(mx_sas_record_trust(p$a,
                list(user_id = p$a$user_id, device_id = "A"), tempfile(), now = 101),
                "human confirmation")
            mx_sas_confirm(p$a, TRUE, now = 101)
            transfer(p$a, p$b)
            expect_identical(mx_sas_status(p$a)$phase, "verified")
            expect_identical(mx_sas_status(p$b)$phase, "verified")
            expect_false(mx_sas_status(p$a)$local_trust_recorded)
        }
    }

    # The Matrix formulas at the two extrema, independent of key agreement.
    low <- mx.client:::sas_display(as.raw(rep(0, 6)))
    high <- mx.client:::sas_display(as.raw(rep(255, 6)))
    expect_equal(low$decimal, rep(1000, 3))
    expect_equal(high$decimal, rep(9191, 3))
    expect_identical(low$descriptions, rep("Dog", 7))
    expect_identical(high$descriptions, rep("Pin", 7))
    expect_equal(length(mx.client:::sas_emoji()$emoji), 64L)

    p <- exchange(pair())
    mx_sas_confirm(p$a, FALSE, now = 101)
    expect_identical(mx_sas_status(p$a)$cancel_code, "m.mismatched_sas")
    transfer(p$a, p$b)
    expect_identical(mx_sas_status(p$b)$phase, "cancelled")
    expect_equal(length(mx_sas_outgoing(p$b)), 0L)
    expect_error(mx_sas_confirm(exchange(pair())$a, NA, now = 101), "explicitly")
    expect_error(mx_sas_receive(pair()$a, now = NA), "finite")
    expect_error(mx_sas_receive(pair()$a, now = numeric()), "finite")

    # Timeouts: request prompt is two minutes, active exchange is ten minutes.
    p <- pair()
    mx_sas_receive(p$b, now = 220)
    expect_identical(mx_sas_status(p$b)$cancel_code, "m.timeout")
    p <- exchange(pair())
    mx_sas_receive(p$a, now = 250)
    expect_identical(mx_sas_status(p$a)$phase, "sas")
    mx_sas_receive(p$a, now = 700)
    expect_identical(mx_sas_status(p$a)$cancel_code, "m.timeout")
    expect_false(mx_sas_status(p$a)$local_trust_recorded)

    # Transport retry retains the exact pending payload and id.
    p <- pair()
    mx_sas_accept(p$b, now = 100)
    pending <- mx_sas_outgoing(p$b)
    expect_identical(mx_sas_outgoing(p$b), pending)
    other <- pair()
    mx_sas_accept(other$b, now = 100)
    # Equal peer-supplied transaction ids must not collide in our HTTP scope.
    expect_identical(other$b$transaction_id, p$b$transaction_id)
    expect_false(identical(mx_sas_outgoing(other$b)[[1]]$id, pending[[1]]$id))
    expect_error(mx_sas_outgoing(p$b, "wrong-id"), "unknown")
    transfer(p$b, p$a)
    start <- mx_sas_outgoing(p$a)[[1]]
    ev <- list(type = start$type, content = start$content, sender = p$a$user_id)
    mx_sas_receive(p$b, ev, now = 101)
    accepted <- mx_sas_outgoing(p$b)
    mx_sas_receive(p$b, ev, now = 101)
    expect_identical(mx_sas_outgoing(p$b), accepted)
    ev$content$hashes <- list("sha512")
    mx_sas_receive(p$b, ev, now = 101)
    expect_identical(mx_sas_status(p$b)$cancel_code, "m.unexpected_message")

    # Wrong sender/device/transaction/room never advances the transaction.
    for (field in c("sender", "device", "transaction", "room", "relation")) {
        p <- pair("!room:example.org")
        mx_sas_accept(p$b, now = 100)
        transfer(p$b, p$a, function(e) {
            if (field == "sender") e$sender <- "@mallory:example.org"
            if (field == "device") e$content$from_device <- "OTHER"
            if (field == "transaction") e$content$`m.relates_to`$event_id <- "other"
            if (field == "room") e$room_id <- "!other:example.org"
            if (field == "relation") e$content$`m.relates_to` <- "malformed"
            e
        })
        expect_identical(mx_sas_status(p$a)$phase, "requested")
    }

    # Commitment binds the full start including transport relation fields.
    p <- pair("!room:example.org")
    mx_sas_accept(p$b, now = 100)
    transfer(p$b, p$a)
    transfer(p$a, p$b, function(e) {e$content$extra <- "tampered"; e})
    transfer(p$b, p$a)
    transfer(p$a, p$b)
    transfer(p$b, p$a)
    expect_identical(mx_sas_status(p$a)$cancel_code, "m.mismatched_commitment")

    # Corrupt a valid peer MAC, remove the master, or alter the key-list MAC.
    for (fault in c("mac", "master", "keys")) {
        p <- exchange(pair())
        mx_sas_confirm(p$b, TRUE, now = 101)
        transfer(p$b, p$a, function(e) {
            if (fault == "mac") e$content$mac[[1]] <- "***"
            if (fault == "master") e$content$mac <- e$content$mac["ed25519:B"]
            if (fault == "keys") e$content$keys <- "***"
            e
        })
        expect_identical(mx_sas_status(p$a)$cancel_code, "m.key_mismatch")
        expect_false(mx_sas_status(p$a)$peer_mac_valid)
    }

    # A real device-only proof differs from dropping a key out of a two-key
    # MAC. FluffyChat sends this when its own master is not locally verified.
    for (corrupt in c(FALSE, TRUE)) {
        p <- exchange(pair())
        info <- mx.client:::sas_info(p$b, mac = TRUE)
        id <- "ed25519:B"
        content <- list(transaction_id = "transaction", mac = setNames(list(
            mx.crypto::mxc_sas_mac(p$b$crypto, bk[[id]], paste0(info, id))), id),
            keys = mx.crypto::mxc_sas_mac(p$b$crypto, id, paste0(info, "KEY_IDS")))
        if (corrupt) content$keys <- "***"
        mx_sas_receive(p$a, list(type = "m.key.verification.mac",
            sender = p$b$user_id, content = content), now = 101)
        status <- mx_sas_status(p$a)
        expect_identical(status$cancel_code, "m.key_mismatch")
        expect_false(status$peer_mac_valid)
        expect_false(status$local_trust_recorded)
        if (corrupt) expect_null(status$cancel_detail) else {
            expect_identical(status$cancel_detail, "peer_master_missing")
            expect_message(mx_sas_console(p$a, function() list(), function(e) NULL,
                function(sas) stop("must not record trust"), input = function(p) "yes"),
                "did not authenticate its master key")
        }
    }

    # No agreement on modern algorithms must fail before showing a SAS.
    p <- pair()
    mx_sas_accept(p$b, now = 100)
    transfer(p$b, p$a)
    transfer(p$a, p$b, function(e) {
        e$content$message_authentication_codes <- list("hkdf-hmac-sha256"); e
    })
    expect_identical(mx_sas_status(p$b)$cancel_code, "m.unknown_method")

    # Simultaneous starts select the lexically smaller identity's start.
    p <- pair()
    mx_sas_accept(p$b, now = 100)
    transfer(p$b, p$a)
    mx_sas_start(p$b, now = 101)
    transfer(p$b, p$a)
    transfer(p$a, p$b)
    for (i in 1:2) {transfer(p$b, p$a); transfer(p$a, p$b)}
    expect_identical(mx_sas_status(p$a)$phase, "sas")
    expect_identical(mx_sas_status(p$a)$decimal, mx_sas_status(p$b)$decimal)

    # Done before key authentication cannot grant trust or complete the flow.
    p <- exchange(pair())
    mx_sas_receive(p$a, list(type = "m.key.verification.done",
        sender = p$b$user_id, content = list(transaction_id = "transaction")), now = 101)
    expect_identical(mx_sas_status(p$a)$cancel_code, "m.unexpected_message")
})
