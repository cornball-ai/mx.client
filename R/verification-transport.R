# A standalone console is a Matrix client, not a second diagnostic sync loop.
# Only one process may own this account, its cursor, and its crypto store.
verification_context <- function(client, store_dir) {
    required <- file.path(store_dir, c("pickle.key", "account.pickle",
        "cross-signing.json", "sessions.json"))
    if (!all(file.exists(required)) || file.info(required[1])$size != 32L) {
        stop("mx.client: an existing initialized crypto store is required",
            call. = FALSE)
    }
    if (is.null(attr(client, "path"))) {
        stop("mx.client: load the client from its existing config path first",
            call. = FALSE)
    }
    # Polling saves a new config object; the caller's original list remains
    # stale. Resume from disk on every attempt, including after interruption.
    saved <- mx_client_load(path = attr(client, "path"),
        app = attr(client, "app") %||% "mx.client")
    identity_fields <- c("server", "user_id", "device_id")
    if (!all(vapply(identity_fields, function(field) {
        identical(saved[[field]], client[[field]])
    }, logical(1)))) {
        stop("mx.client: saved Matrix identity changed; reload the client ",
            "config before verification", call. = FALSE)
    }
    client <- saved
    ctx <- new.env(parent = emptyenv())
    ctx$client <- client
    ctx$store_dir <- store_dir
    # Verify the token and store describe this exact device before consuming sync.
    identity <- mx.api::mx_whoami(mx_client_session(client))
    if (!identical(identity$user_id, client$user_id) ||
        !identical(identity$device_id, client$device_id)) {
        stop("mx.client: access token belongs to a different Matrix device",
            call. = FALSE)
    }
    sas_identity(client, store_dir, client$user_id, client$device_id)
    ctx$account <- mx_crypto_account(store_dir)
    ctx$sessions <- mx_crypto_sessions_load(store_dir)
    ctx$master <- mx.crypto::mxc_signing_key_public(
        mx_crypto_cross_signing_load(store_dir)$master)
    ctx$pending <- list()
    ctx$messages <- list()
    ctx
}

verification_poll <- function(ctx, peer_user_id, on_messages) {
    response <- mx_sync_update(ctx$client, timeout = 1000L, save = FALSE)
    devices <- tryCatch(mx_crypto_known_devices(ctx$client,
        unique(c(ctx$client$user_id, peer_user_id)), self_master_key = ctx$master),
        error = function(e) {
            warning("mx.client: device lookup failed: ", conditionMessage(e),
                call. = FALSE)
            NULL
        })
    keys <- mx.crypto::mxc_account_identity_keys(ctx$account)
    res <- mx_crypto_process_sync(ctx$account, ctx$sessions, response$sync,
        keys$curve25519, ctx$client$user_id, devices, ctx$client$device_id)
    ctx$sessions <- res$sessions
    # No transport or operator callback before ratchets and cursor are saved.
    mx_crypto_account_save(ctx$account, ctx$store_dir)
    mx_crypto_sessions_save(ctx$sessions, ctx$store_dir)
    ctx$client <- mx_client_save(response$client)
    normal <- c(mx_extract_text_events(response$sync, ctx$client$user_id), res$events)
    ctx$messages <- c(ctx$messages, normal)
    if (length(normal)) on_messages(normal)
    # Failed key requests remain pending for a future poll with the same id.
    if (length(res$key_requests)) tryCatch({
        mx_crypto_send_key_requests(ctx$client, res$key_requests)
        ctx$sessions <- mx_crypto_mark_key_requests_sent(ctx$sessions, res$key_requests)
        mx_crypto_sessions_save(ctx$sessions, ctx$store_dir)
    }, error = function(e) warning("mx.client: room-key request deferred: ",
        conditionMessage(e), call. = FALSE))
    if (length(res$key_request_cancellations)) tryCatch(
        mx_crypto_send_key_requests(ctx$client, res$key_request_cancellations),
        error = function(e) warning("mx.client: room-key cancellation failed: ",
            conditionMessage(e), call. = FALSE))
    res$verification_events
}

verification_recipients <- function(ctx, peer) {
    devices <- mx_crypto_known_devices(ctx$client,
        unique(c(ctx$client$user_id, peer)), strict = TRUE,
        self_master_key = ctx$master)
    devices <- Filter(function(d) !(identical(d$user_id, ctx$client$user_id) &&
        identical(d$device_id, ctx$client$device_id)), devices)
    need <- vapply(devices, function(d) is.null(ctx$sessions$olm[[d$curve25519]]),
        logical(1))
    recipients <- c(devices[!need], mx_crypto_claim_otks(ctx$client,
        devices[need], strict = TRUE))
    recipients <- Filter(function(d) !is.null(d$otk) ||
        !is.null(ctx$sessions$olm[[d$curve25519]]), recipients)
    if (!any(vapply(recipients, function(d) identical(d$user_id, peer), logical(1)))) {
        stop("mx.client: no usable peer device for encrypted verification",
            call. = FALSE)
    }
    recipients
}

verification_send <- function(ctx, envelope, encrypted) {
    s <- mx_client_session(ctx$client)
    id <- envelope$id
    if (is.null(envelope$room_id)) {
        mx.api::mx_send_to_device(s, envelope$type, stats::setNames(
            list(stats::setNames(list(envelope$content), envelope$device_id)),
            envelope$user_id), txn_id = id)
    } else if (!encrypted) {
        mx.api::mx_send_event(s, envelope$room_id, envelope$type,
            envelope$content, txn_id = id)
    } else {
        pending <- ctx$pending[[id]]
        if (is.null(pending)) {
            recipients <- verification_recipients(ctx, envelope$user_id)
            old_shared <- ctx$sessions$megolm_out[[envelope$room_id]]$shared
            keys <- mx.crypto::mxc_account_identity_keys(ctx$account)
            pending <- mx_crypto_encrypt_for_devices(ctx$account, ctx$sessions,
                envelope$room_id, envelope$content, keys$curve25519,
                ctx$client$device_id, recipients, ctx$client$user_id,
                event_type = envelope$type)
            ctx$sessions <- pending$sessions
            # Do not persist delivery markers for room keys not yet sent.
            ctx$sessions$megolm_out[[envelope$room_id]]$shared <-
                old_shared %||% character()
            ctx$pending[[id]] <- pending
        }
        # Saving is retried before sending after an earlier save failure too.
        mx_crypto_account_save(ctx$account, ctx$store_dir)
        mx_crypto_sessions_save(ctx$sessions, ctx$store_dir)
        for (i in seq_along(pending$to_device)) {
            item <- pending$to_device[[i]]
            mx.api::mx_send_to_device(s, "m.room.encrypted", stats::setNames(
                list(stats::setNames(list(item$content), item$device_id)), item$user_id),
                txn_id = paste0(id, "-key-", i))
        }
        mx.api::mx_send_event(s, envelope$room_id, "m.room.encrypted",
            pending$event, txn_id = id)
        ctx$sessions$megolm_out[[envelope$room_id]]$shared <-
            pending$sessions$megolm_out[[envelope$room_id]]$shared
        mx_crypto_sessions_save(ctx$sessions, ctx$store_dir)
        ctx$pending[[id]] <- NULL
    }
    invisible(NULL)
}
