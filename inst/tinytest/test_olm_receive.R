library(tinytest)

if (!requireNamespace("mx.crypto", quietly = TRUE)) {
    exit_file("mx.crypto not available")
}
library(mx.client)

local({
    room <- "!room:example.org"
    alice_id <- "@alice:example.org"
    bob_id <- "@bob:example.org"
    store <- tempfile("olm-receive-")
    on.exit(unlink(store, recursive = TRUE), add = TRUE)

    # Alice opens the session. Bob's first reply must use type 1, even
    # though Alice has never created an inbound session for Bob.
    pair <- function() {
        alice <- mx.crypto::mxc_account_new()
        bob <- mx.crypto::mxc_account_new()
        ak <- mx.crypto::mxc_account_identity_keys(alice)
        bk <- mx.crypto::mxc_account_identity_keys(bob)
        mx.crypto::mxc_account_generate_one_time_keys(bob, 1L)
        out <- mx.crypto::mxc_olm_create_outbound(alice, bk$curve25519,
            mx.crypto::mxc_account_one_time_keys(bob)[[1L]])
        pre <- mx.crypto::mxc_olm_encrypt(out, charToRaw("initial message"))
        inc <- mx.crypto::mxc_olm_create_inbound(bob, ak$curve25519,
                                               pre$body)$session
        list(alice = alice, bob = bob, ak = ak, bk = bk,
             out = out, inc = inc)
    }
    share <- function(session, sender_keys, recipient_keys,
                      sender_id, recipient_id, body = "reply") {
        group <- mx.crypto::mxc_megolm_outbound_new()
        content <- mx_crypto_room_key_payload(session,
            sender_keys$curve25519, recipient_keys$curve25519, room, group,
            sender_id, sender_keys$ed25519, recipient_id,
            recipient_keys$ed25519)
        event <- mx_crypto_encrypt_event(group,
            list(msgtype = "m.text", body = body), room,
            sender_keys$curve25519, "PEER")
        list(content = content, event = event, sender = sender_id,
             key = paste(room, event$session_id, sep = "|"))
    }
    sync <- function(shares) {
        list(to_device = list(events = lapply(shares, function(x) {
            list(type = "m.room.encrypted", sender = x$sender,
                 content = x$content)
        })), rooms = list(join = setNames(list(list(timeline = list(
            events = lapply(seq_along(shares), function(i) {
                x <- shares[[i]]
                list(type = "m.room.encrypted", event_id = paste0("$", i),
                     sender = x$sender, content = x$event)
            })))), room)))
    }
    process <- function(f, sessions, shares, alice = TRUE, devices = NULL) {
        tryCatch(mx_crypto_process_sync(
            if (alice) f$alice else f$bob, sessions, sync(shares),
            if (alice) f$ak$curve25519 else f$bk$curve25519,
            self_id = if (alice) alice_id else bob_id,
            self_device_id = "SELF", devices = devices),
            error = function(e) e)
    }

    # Regression: initiator receives a room key over its outbound session,
    # including after persistence. A different inbound session for the same
    # peer must fail locally and not prevent trying the outbound session.
    for (wrong_inbound in c(FALSE, TRUE)) {
        f <- pair()
        sessions <- mx_crypto_sessions_new()
        sessions$olm[[f$bk$curve25519]] <- f$out
        if (wrong_inbound) {
            mx.crypto::mxc_account_generate_one_time_keys(f$alice, 1L)
            other <- mx.crypto::mxc_olm_create_outbound(f$bob,
                f$ak$curve25519,
                mx.crypto::mxc_account_one_time_keys(f$alice)[[1L]])
            pre <- mx.crypto::mxc_olm_encrypt(other, charToRaw("other session"))
            sessions$olm_in[[f$bk$curve25519]] <-
                mx.crypto::mxc_olm_create_inbound(f$alice,
                    f$bk$curve25519, pre$body)$session
        }
        msg <- share(f$inc, f$bk, f$ak, bob_id, alice_id)
        expect_identical(msg$content$ciphertext[[f$ak$curve25519]]$type, 1L)
        sessions$key_requests[[msg$key]] <- mx.client:::mx_crypto_key_request(
            alice_id, "SELF", room, msg$event$session_id,
            f$bk$curve25519, bob_id)
        mx_crypto_sessions_save(sessions, store)
        sessions <- mx_crypto_sessions_load(store)
        devices <- list(list(user_id = bob_id, device_id = "PEER",
                            curve25519 = f$bk$curve25519,
                            ed25519 = f$bk$ed25519))
        res <- process(f, sessions, list(msg), devices = devices)
        expect_false(inherits(res, "error"))
        if (!inherits(res, "error")) {
            expect_equal(length(res$events), 1L)
            expect_true(msg$key %in% names(res$sessions$megolm_in))
            expect_equal(length(res$sessions$olm_in), as.integer(wrong_inbound))
            expect_equal(length(res$sessions$key_requests), 0L)
            expect_equal(length(res$key_request_cancellations), 1L)
            if (length(res$events)) {
                expect_identical(res$events[[1L]]$body, "reply")
                expect_true(res$events[[1L]]$sender_verified)
            }
            # Persist the advanced outbound receive ratchet, then accept
            # another room-key share on the same session.
            mx_crypto_sessions_save(res$sessions, store)
            msg2 <- share(f$inc, f$bk, f$ak, bob_id, alice_id, "after reload")
            res2 <- process(f, mx_crypto_sessions_load(store), list(msg2))
            expect_false(inherits(res2, "error"))
            if (!inherits(res2, "error")) {
                expect_equal(length(res2$events), 1L)
                if (length(res2$events)) {
                    expect_identical(res2$events[[1L]]$body, "after reload")
                    expect_false(res2$events[[1L]]$sender_verified)
                }
            }
        }
    }

    # Alice has received no reply, so further messages on her existing
    # session remain prekey messages. Bob's OTK has already been consumed.
    f <- pair()
    sessions <- mx_crypto_sessions_new()
    sessions$olm_in[[f$ak$curve25519]] <- f$inc
    msg <- share(f$out, f$ak, f$bk, alice_id, bob_id, "second prekey")
    expect_identical(msg$content$ciphertext[[f$bk$curve25519]]$type, 0L)
    expect_equal(length(mx.crypto::mxc_account_one_time_keys(f$bob)), 0L)
    res <- process(f, sessions, list(msg), alice = FALSE)
    expect_false(inherits(res, "error"))
    if (!inherits(res, "error")) {
        expect_equal(length(res$events), 1L)
        expect_true(msg$key %in% names(res$sessions$megolm_in))
        expect_identical(res$sessions$olm_in[[f$ak$curve25519]], f$inc)

        # Exact replay cannot decrypt twice, but it must not abort the batch
        # or prevent a later valid prekey message from installing its key.
        later <- share(f$out, f$ak, f$bk, alice_id, bob_id, "after replay")
        expect_warning(replayed <- process(f, res$sessions,
            list(msg, later), alice = FALSE), "cannot decrypt Olm")
        expect_false(inherits(replayed, "error"))
        if (!inherits(replayed, "error")) {
            expect_true(later$key %in% names(replayed$sessions$megolm_in))
            expect_equal(length(replayed$events), 2L)
        }
    }

    # Invalid ciphertext and failed inbound creation must be contained.
    # A valid key share later in the same batch still decrypts its event.
    for (type in c(0L, 1L)) {
        f <- pair()
        sessions <- mx_crypto_sessions_new()
        sessions$olm[[f$bk$curve25519]] <- f$out
        good <- share(f$inc, f$bk, f$ak, bob_id, alice_id)
        bad <- good
        bad$content$ciphertext[[f$ak$curve25519]] <- list(type = type,
                                                       body = "bad base64!")
        expect_warning(res <- process(f, sessions, list(bad, good)),
                       "cannot decrypt Olm")
        expect_false(inherits(res, "error"))
        if (!inherits(res, "error")) {
            expect_true(good$key %in% names(res$sessions$megolm_in))
            expect_equal(length(res$events), 2L)
        }
    }

    # The public one-payload handler accepts existing session handles too.
    for (prekey in c(FALSE, TRUE)) {
        f <- pair()
        msg <- if (prekey) share(f$out, f$ak, f$bk, alice_id, bob_id) else
            share(f$inc, f$bk, f$ak, bob_id, alice_id)
        result <- tryCatch(mx_crypto_handle_to_device(
            if (prekey) f$bob else f$alice,
            if (prekey) f$bk$curve25519 else f$ak$curve25519, msg$content,
            self_id = if (prekey) bob_id else alice_id,
            olm_sessions = list(if (prekey) f$inc else f$out)),
            error = function(e) e)
        expect_false(inherits(result, "error"))
        if (!inherits(result, "error")) {
            expect_identical(result$type, "m.room_key")
            expect_identical(result$content$session_id, msg$event$session_id)
            expect_false(result$sender_bound)
        }
    }
    # Receiving on the inbound map also works after the peer sees a reply
    # and switches from prekey to normal messages.
    f <- pair()
    ack <- mx.crypto::mxc_olm_encrypt(f$inc, charToRaw("ack"))
    expect_identical(rawToChar(mx.crypto::mxc_olm_decrypt(
        f$out, ack$type, ack$body)), "ack")
    msg <- share(f$out, f$ak, f$bk, alice_id, bob_id)
    expect_identical(msg$content$ciphertext[[f$bk$curve25519]]$type, 1L)
    sessions <- mx_crypto_sessions_new()
    sessions$olm_in[[f$ak$curve25519]] <- f$inc
    res <- process(f, sessions, list(msg), alice = FALSE)
    expect_false(inherits(res, "error"))
    if (!inherits(res, "error")) expect_equal(length(res$events), 1L)

    # A genuinely new prekey session still opens after all existing
    # sessions fail, replacing only the inbound entry for that peer.
    f <- pair()
    mx.crypto::mxc_account_generate_one_time_keys(f$bob, 1L)
    fresh <- mx.crypto::mxc_olm_create_outbound(f$alice, f$bk$curve25519,
        mx.crypto::mxc_account_one_time_keys(f$bob)[[1L]])
    msg <- share(fresh, f$ak, f$bk, alice_id, bob_id)
    sessions <- mx_crypto_sessions_new()
    sessions$olm_in[[f$ak$curve25519]] <- f$inc
    res <- process(f, sessions, list(msg), alice = FALSE)
    expect_false(inherits(res, "error"))
    if (!inherits(res, "error")) {
        expect_equal(length(res$events), 1L)
        expect_false(identical(res$sessions$olm_in[[f$ak$curve25519]], f$inc))
        expect_equal(length(mx.crypto::mxc_account_one_time_keys(f$bob)), 0L)
    }

    # Decrypting a malformed JSON body has already advanced the ratchet.
    # Retain it and accept the next good key in the same batch.
    f <- pair()
    malformed <- mx.crypto::mxc_olm_encrypt(f$inc, charToRaw("{bad json"))
    good <- share(f$inc, f$bk, f$ak, bob_id, alice_id)
    bad <- good
    bad$content$ciphertext[[f$ak$curve25519]] <- malformed
    sessions <- mx_crypto_sessions_new()
    sessions$olm[[f$bk$curve25519]] <- f$out
    expect_warning(res <- process(f, sessions, list(bad, good)),
                   "malformed Olm plaintext")
    expect_false(inherits(res, "error"))
    if (!inherits(res, "error")) {
        expect_true(good$key %in% names(res$sessions$megolm_in))
        expect_equal(length(res$events), 2L)
    }

    # No established session: do not create one from a normal message.
    f <- pair()
    msg <- share(f$inc, f$bk, f$ak, bob_id, alice_id)
    expect_warning(res <- process(f, mx_crypto_sessions_new(), list(msg)),
                   "cannot decrypt Olm")
    expect_false(inherits(res, "error"))
    if (!inherits(res, "error")) {
        expect_equal(length(res$events), 0L)
        expect_equal(length(res$sessions$olm_in), 0L)
        expect_equal(length(res$sessions$megolm_in), 0L)
    }

    # Established-session success still must pass the recipient checks.
    f <- pair()
    msg <- share(f$inc, f$bk, f$ak, bob_id, "@other:example.org")
    expect_warning(result <- mx_crypto_handle_to_device(
        f$alice, f$ak$curve25519, msg$content, self_id = alice_id,
        olm_sessions = list(f$out)), "not @alice")
    expect_null(result)
    msg <- share(f$inc, f$bk, f$ak, bob_id, alice_id)
    expect_warning(result <- mx_crypto_handle_to_device(
        f$alice, f$ak$curve25519, msg$content, self_id = alice_id,
        self_ed25519 = "wrong", olm_sessions = list(f$out)),
        "recipient_keys")
    expect_null(result)

    # The standalone handler contains failed inbound creation too.
    f <- pair()
    msg <- share(f$out, f$ak, f$bk, alice_id, bob_id)
    expect_warning(result <- mx_crypto_handle_to_device(
        f$bob, f$bk$curve25519, msg$content, self_id = bob_id),
        "cannot decrypt Olm")
    expect_null(result)
    for (type in list(NULL, NA_integer_, 2L, c(0L, 1L))) {
        malformed <- msg$content
        malformed$ciphertext[[f$bk$curve25519]]$type <- type
        expect_warning(result <- mx_crypto_handle_to_device(
            f$bob, f$bk$curve25519, malformed, self_id = bob_id,
            olm_sessions = list(f$inc)), "malformed Olm to-device")
        expect_null(result)
    }
})
