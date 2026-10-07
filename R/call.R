# MatrixRTC calls over LiveKit, as Element Call and FluffyChat run them:
# a per-device membership state event, a media token from the LiveKit
# JWT service, and per-participant media keys exchanged as Olm-encrypted
# to-device events. Media itself goes through the livekitr package.
#
# Wire format (both clients read, 2026-10): membership is a state event
# org.matrix.msc3401.call.member with state key "_<user>_<device>_m.call",
# keys are io.element.call.encryption_keys to-device events, and the
# LiveKit participant identity is "<user>:<device>".

MX_CALL_MEMBER <- "org.matrix.msc3401.call.member"
MX_CALL_KEYS <- "io.element.call.encryption_keys"
MX_CALL_EXPIRES_MS <- 4 * 60 * 60 * 1000
MX_CALL_REFRESH_S <- 60 * 60
# A joiner inside this window gets the current key; later, the key rotates.
MX_CALL_KEY_GRACE_S <- 10
# Key indexes cycle below 255: FluffyChat's key ring has 255 slots.
MX_CALL_KEY_INDEXES <- 255L

mx_call_now_ms <- function(now = Sys.time()) {
    floor(as.numeric(now) * 1000)
}

mx_call_state_key <- function(user_id, device_id) {
    paste0("_", user_id, "_", device_id, "_m.call")
}

mx_call_identity <- function(user_id, device_id) {
    paste(user_id, device_id, sep = ":")
}

# Content of this device's membership event. created_ts is what Element
# reads, created_at what FluffyChat reads; both fall back to the event's
# origin_server_ts, so sending both only keeps the expiry exact.
mx_call_member_content <- function(user_id, device_id, service_url, room_id,
                                   intent = "voice", now = Sys.time()) {
    stopifnot(intent %in% c("voice", "video"))
    ts <- mx_call_now_ms(now)
    list(
         application = "m.call",
         call_id = "",
         scope = "m.room",
         device_id = device_id,
         membershipID = mx_call_identity(user_id, device_id),
         expires = MX_CALL_EXPIRES_MS,
         `m.call.intent` = intent,
         focus_active = list(type = "livekit",
                             focus_selection = "oldest_membership"),
         foci_preferred = list(list(type = "livekit",
                                    livekit_service_url = service_url,
                                    livekit_alias = room_id)),
         created_ts = ts,
         created_at = ts
    )
}

#' Active call memberships in a room's state
#'
#' Reads the \code{org.matrix.msc3401.call.member} state events out of a
#' room's full state (\code{mx.api::mx_room_state()}) and keeps the ones
#' that count as in the call: non-empty content, a LiveKit focus, and an
#' expiry (\code{created_ts}, or \code{created_at}, or the event's own
#' timestamp, plus \code{expires}, default 4 hours) still in the future.
#'
#' @param state List of state events.
#' @param now The current time.
#' @return A list of members, each \code{list(user_id, device_id,
#'   identity, membership_id, service_urls, expires_at)}, where
#'   \code{identity} is the member's LiveKit participant identity
#'   \code{"<user>:<device>"} and \code{service_urls} the LiveKit JWT
#'   services it prefers.
#' @examples
#' state <- list(list(type = "org.matrix.msc3401.call.member",
#'     sender = "@alice:example.org", origin_server_ts = 1e12,
#'     content = list(application = "m.call", device_id = "PHONE",
#'         focus_active = list(type = "livekit"),
#'         foci_preferred = list(list(type = "livekit",
#'             livekit_service_url = "https://jwt.example.org")))))
#' mx_call_members(state, now = as.POSIXct(1e9, origin = "1970-01-01"))
#' @export
mx_call_members <- function(state, now = Sys.time()) {
    now_ms <- mx_call_now_ms(now)
    members <- list()
    for (ev in state) {
        if (!identical(ev$type, MX_CALL_MEMBER)) next
        c <- ev$content
        if (!is.list(c) || !length(c)) next
        if (!identical(c$focus_active$type, "livekit")) next
        if (!is.character(c$device_id) || !nzchar(c$device_id)) next
        if (!is.character(ev$sender) || !nzchar(ev$sender)) next
        created <- c$created_ts %||% c$created_at %||% ev$origin_server_ts
        expires <- c$expires %||% MX_CALL_EXPIRES_MS
        if (!is.numeric(created) || !is.numeric(expires)) next
        expires_at <- created + expires
        if (expires_at <= now_ms) next
        urls <- character()
        for (focus in c$foci_preferred %||% list()) {
            if (identical(focus$type, "livekit") &&
                is.character(focus$livekit_service_url)) {
                urls <- c(urls, focus$livekit_service_url)
            }
        }
        members[[length(members) + 1L]] <- list(
            user_id = ev$sender,
            device_id = c$device_id,
            identity = mx_call_identity(ev$sender, c$device_id),
            membership_id = c$membershipID %||%
            mx_call_identity(ev$sender, c$device_id),
            service_urls = urls,
            expires_at = expires_at)
    }
    members
}

#' Find the LiveKit JWT service for a room's call
#'
#' Tries, in order, the services the current call members advertise in
#' their memberships, the homeserver's RTC transports
#' (\code{mx.api::mx_rtc_transports()}), and the
#' \code{org.matrix.msc4143.rtc_foci} entry of the server's client
#' well-known file.
#'
#' @param client Matrix client config.
#' @param members Current members from \code{\link{mx_call_members}}.
#' @return The service URL, a string.
#' @examples
#' \dontrun{
#' mx_call_service_url(client, members)
#' }
#' @export
mx_call_service_url <- function(client, members = list()) {
    for (member in members) {
        if (length(member$service_urls)) {
            return(member$service_urls[[1L]])
        }
    }
    s <- mx_client_session(client)
    for (transport in mx.api::mx_rtc_transports(s)) {
        if (identical(transport$type, "livekit") &&
            is.character(transport$livekit_service_url)) {
            return(transport$livekit_service_url)
        }
    }
    server_name <- sub("^@[^:]+:", "", client$user_id)
    well_known <- mx.api::mx_well_known_client(server_name)
    foci <- well_known[["org.matrix.msc4143.rtc_foci"]]
    if (is.list(foci) && !is.null(foci$livekit_service_url)) {
        foci <- list(foci)
    }
    for (focus in foci %||% list()) {
        if (is.character(focus$livekit_service_url)) {
            return(focus$livekit_service_url)
        }
    }
    stop("no LiveKit JWT service found: nobody in the call advertises one, ",
         "the homeserver lists no RTC transports, and ", server_name,
         " has no rtc_foci in its well-known file", call. = FALSE)
}

# ---- media keys -------------------------------------------------------

mx_call_b64 <- function(bytes) {
    jsonlite::base64_enc(bytes)
}

# Accepts standard or URL-safe alphabets, padded or not, as the Element
# decoder does.
mx_call_b64_decode <- function(x) {
    x <- gsub("[\r\n= ]", "", chartr("-_", "+/", x))
    pad <- (4L - nchar(x) %% 4L) %% 4L
    jsonlite::base64_dec(paste0(x, strrep("=", pad)))
}

# Content of a key event: the key the receiver should use for this
# device's media. FluffyChat casts every field but sent_ts, so all of them
# are always present.
# A superset that both consumers accept: FluffyChat / matrix-dart-sdk
# reads top-level call_id + device_id + keys (it sends and expects the key
# as a room event); Element Call reads member + keys (to-device). Sending
# this one object by either transport reaches both.
mx_call_key_content <- function(key, index, user_id, device_id, room_id,
                                now = Sys.time()) {
    list(
         call_id = "",
         device_id = device_id,
         # keys is an array of {index, key}; the wrapping list makes JSON
         # serialize it as an array even with a single entry.
         keys = list(list(index = as.integer(index), key = mx_call_b64(key))),
         member = list(id = mx_call_identity(user_id, device_id),
                       claimed_device_id = device_id),
         room_id = room_id,
         session = list(application = "m.call", call_id = "", scope = "m.room"),
         sent_ts = mx_call_now_ms(now)
    )
}

# Normalize the content's `keys` field to a list of {index, key}. The
# wire sends an array; depending on how the Olm plaintext was parsed it
# arrives as an unnamed list of objects (simplifyVector = FALSE), a data
# frame (simplifyVector = TRUE), and we also tolerate a single {index,
# key} object from a non-conformant sender.
mx_call_key_entries <- function(keys) {
    if (is.null(keys)) {
        return(list())
    }
    if (is.data.frame(keys)) {
        return(lapply(seq_len(nrow(keys)), function(i) {
            list(index = keys$index[[i]], key = keys$key[[i]])
        }))
    }
    if (!is.null(names(keys)) && !is.null(keys$index)) {
        return(list(list(index = keys$index, key = keys$key)))
    }
    if (is.list(keys)) {
        return(Filter(function(e) is.list(e) && !is.null(e$index), keys))
    }
    list()
}

#' Read a call key event
#'
#' Parses a decrypted \code{io.element.call.encryption_keys} to-device
#' event (from the \code{to_device} list of
#' \code{\link{mx_crypto_process_sync}}) into the LiveKit identities and
#' keys to set. The event's \code{keys} field is an array, so one event
#' can carry several keys at different indices; each becomes one entry.
#'
#' @param event List with \code{type}, \code{content} and \code{sender}.
#' @param room_id The call's room; keys for other rooms are ignored.
#' @return A list of \code{list(identity, key, index)}, with \code{key} a
#'   raw vector, one per usable key in the event; empty when the event is
#'   not a usable key for this room.
#' @examples
#' ev <- list(type = "io.element.call.encryption_keys",
#'     sender = "@alice:example.org",
#'     content = list(
#'         keys = list(list(index = 3, key = "AAECAwQFBgcICQoLDA0ODw==")),
#'         member = list(claimed_device_id = "PHONE"), room_id = "!r:example.org"))
#' mx_call_key_parse(ev, "!r:example.org")
#' @export
mx_call_key_parse <- function(event, room_id) {
    if (!identical(event$type, MX_CALL_KEYS)) return(list())
    c <- event$content
    # A to-device event names its room in the content; a room event does
    # not (its room is the event's own, matched by the caller). Enforce
    # content$room_id only when it is present.
    if (!is.null(c$room_id) && !identical(c$room_id, room_id)) return(list())
    # Element Call uses member$claimed_device_id; FluffyChat uses a
    # top-level device_id.
    device <- c$member$claimed_device_id %||% c$device_id
    if (!is.character(event$sender) || !is.character(device) ||
        !nzchar(device)) {
        return(list())
    }
    identity <- mx_call_identity(event$sender, device)
    out <- list()
    for (k in mx_call_key_entries(c$keys)) {
        index <- k$index
        key <- k$key
        if (!is.numeric(index) || length(index) != 1L || index < 0 ||
            index != floor(index) || !is.character(key) || length(key) != 1L) {
            next
        }
        bytes <- tryCatch(mx_call_b64_decode(key), error = function(e) NULL)
        if (is.null(bytes) || !length(bytes)) {
            next
        }
        out[[length(out) + 1L]] <- list(identity = identity, key = bytes,
                                        index = as.integer(index))
    }
    out
}

# The key state of one call: our key and index, when the key was made,
# whom it was sent to, and the peers' keys.
mx_call_keys_new <- function() {
    keys <- new.env(parent = emptyenv())
    keys$key <- NULL
    keys$index <- -1L
    keys$created <- NULL
    keys$shared_with <- character()
    keys$peers <- list()
    keys
}

mx_call_keys_rotate <- function(keys, now = Sys.time()) {
    keys$key <- mx_crypto_random_bytes(16L)
    keys$index <- (keys$index + 1L) %% MX_CALL_KEY_INDEXES
    keys$created <- now
    keys$shared_with <- character()
    invisible(keys)
}

#' Decide what to do with the call key when membership changes
#'
#' Implements the rotation policy Element Call and FluffyChat follow: a
#' leaver forces a new key for everyone; a joiner within the grace period
#' after the key was made receives the current key; a joiner after it
#' gets a new key, as does everyone else.
#'
#' @param keys Key state from \code{mx_call_keys_new()} (an environment;
#'   it is not modified).
#' @param identities LiveKit identities of the other members now in the
#'   call.
#' @param now The current time.
#' @param grace Seconds after a key is made during which it is still
#'   handed to joiners instead of rotated.
#' @return \code{list(rotate, targets)}: whether to make a new key, and
#'   the identities to send the (new or current) key to.
#' @examples
#' keys <- mx.client:::mx_call_keys_new()
#' mx_call_key_plan(keys, c("@a:ex:D1", "@b:ex:D2"))
#' @export
mx_call_key_plan <- function(keys, identities, now = Sys.time(),
                             grace = MX_CALL_KEY_GRACE_S) {
    identities <- unique(identities)
    if (is.null(keys$key)) {
        return(list(rotate = TRUE, targets = identities))
    }
    left <- setdiff(keys$shared_with, identities)
    joined <- setdiff(identities, keys$shared_with)
    if (length(left)) {
        return(list(rotate = TRUE, targets = identities))
    }
    if (!length(joined)) {
        return(list(rotate = FALSE, targets = character()))
    }
    age <- as.numeric(difftime(now, keys$created, units = "secs"))
    if (age < grace) {
        list(rotate = FALSE, targets = joined)
    } else {
        list(rotate = TRUE, targets = identities)
    }
}

# Devices of the given identities, with verified keys.
mx_call_devices <- function(client, identities) {
    if (!length(identities)) return(list())
    parts <- regmatches(identities, regexec("^(.*):([^:]+)$", identities))
    user_ids <- unique(vapply(parts, `[`, "", 2L))
    known <- mx_crypto_known_devices(client, user_ids, strict = TRUE)
    Filter(function(d) {
        mx_call_identity(d$user_id, d$device_id) %in% identities
    }, known)
}

# ---- the call object --------------------------------------------------

mx_require_livekitr <- function() {
    if (!requireNamespace("livekitr", quietly = TRUE)) {
        stop("joining the media of a call needs the livekitr package",
             call. = FALSE)
    }
    invisible(TRUE)
}

# Apply a peer's key to the media session, remembering it for a session
# that is not connected yet.
mx_call_apply_peer_key <- function(call, parsed) {
    call$keys$peers[[parsed$identity]] <- parsed[c("key", "index")]
    if (!is.null(call$session)) {
        livekitr::lk_set_e2ee_key(call$session, parsed$key,
                                  identity = parsed$identity,
                                  key_index = parsed$index)
    }
    invisible(NULL)
}

# Send our current key to the given identities, then make sure our own
# media uses it.
mx_call_send_key <- function(call, targets) {
    if (length(targets)) {
        devices <- mx_call_devices(call$client, targets)
        content <- mx_call_key_content(call$keys$key, call$keys$index,
                                       call$client$user_id,
                                       call$client$device_id, call$room_id)
        res <- mx_send_to_device_encrypted(call$client, call$account,
            call$sessions, MX_CALL_KEYS, content,
            devices, call$store_dir)
        call$sessions <- res$sessions
        reached <- vapply(res$sent, function(p) {
            mx_call_identity(p$user_id, p$device_id)
        }, "")
        call$keys$shared_with <- union(call$keys$shared_with,
                                       intersect(targets, reached))
        # FluffyChat / matrix-dart-sdk reads the key from an encrypted
        # ROOM event, not to-device, so also post it there. Guarded: a
        # failure here must not break the to-device path or the call.
        tryCatch({
            user_ids <- unique(sub(":[^:]+$", "", targets))
            room_res <- mx_send_encrypted(call$client, call$account,
                call$sessions, call$room_id, content, call$store_dir,
                member_ids = user_ids, event_type = MX_CALL_KEYS)
            call$sessions <- room_res$sessions
        }, error = function(e) {
            warning("mx.client: could not post the call key as a room event: ",
                    conditionMessage(e), call. = FALSE)
        })
    }
    if (!is.null(call$session)) {
        livekitr::lk_set_e2ee_key(call$session, call$keys$key,
                                  identity = call$identity,
                                  key_index = call$keys$index)
    }
    invisible(NULL)
}

# Reconcile the key state with the current members.
mx_call_update_keys <- function(call, members, now = Sys.time()) {
    others <- setdiff(vapply(members, `[[`, "", "identity"), call$identity)
    plan <- mx_call_key_plan(call$keys, others, now)
    if (plan$rotate) {
        mx_call_keys_rotate(call$keys, now)
    }
    mx_call_send_key(call, plan$targets)
    call$members <- members
    invisible(NULL)
}

mx_call_send_membership <- function(call, now = Sys.time()) {
    content <- mx_call_member_content(call$client$user_id,
                                      call$client$device_id, call$service_url,
                                      call$room_id, call$intent, now)
    tryCatch(
        mx.api::mx_set_state(mx_client_session(call$client), call$room_id,
                             MX_CALL_MEMBER, content,
                             mx_call_state_key(call$client$user_id,
                                               call$client$device_id)),
        mx_error_M_FORBIDDEN = function(e) {
            # Rooms default to power level 50 for state events. Element
            # and FluffyChat set this event type to 0 when they create a
            # room with calls; a room made another way needs the same.
            stop(call$client$user_id, " may not send ", MX_CALL_MEMBER,
                 " in ", call$room_id, ": ", conditionMessage(e),
                 ". The room's m.room.power_levels needs events[\"",
                 MX_CALL_MEMBER, "\"] low enough for every participant ",
                 "(call clients set it to 0).", call. = FALSE)
        })
    call$membership_sent <- now
    invisible(NULL)
}

#' Join a MatrixRTC call
#'
#' Joins the call of a room the way Element Call and FluffyChat do:
#' finds the LiveKit JWT service, trades an OpenID token for a media
#' token, announces this device's membership as a state event, makes a
#' media key and sends it Olm-encrypted to every device already in the
#' call, and, with \code{connect = TRUE}, joins the LiveKit room through
#' \pkg{livekitr} with end-to-end encryption on. The returned call must
#' then be driven with \code{\link{mx_call_handle}} (or
#' \code{\link{mx_call_poll}}) and ended with \code{\link{mx_call_leave}}.
#'
#' @param client Matrix client config.
#' @param account An mx.crypto account handle.
#' @param sessions A session set.
#' @param room_id The room whose call to join.
#' @param intent \code{"voice"} or \code{"video"}, what the membership
#'   announces.
#' @param store_dir Character or NULL. Where the updated crypto sessions
#'   are saved after each key send.
#' @param connect Join the LiveKit room now? \code{FALSE} does everything
#'   on the Matrix side only.
#' @param service_url Character or NULL. The LiveKit JWT service to use
#'   instead of discovering one.
#' @return An object of class \code{"mx_call"}: an environment holding
#'   the \code{client} and \code{sessions} (both updated as the call
#'   runs), the LiveKit \code{session} from \pkg{livekitr} (or NULL), this
#'   device's LiveKit \code{identity}, the current \code{members}, and
#'   the media \code{token}.
#' @examples
#' \dontrun{
#' call <- mx_call_join(client, acct, sessions, "!room:example.org",
#'                      store_dir = store)
#' livekitr::lk_on_audio(call$session, function(pcm, info) {
#'     cat(info$identity, "spoke\n")
#' })
#' repeat mx_call_poll(call)
#' }
#' @export
mx_call_join <- function(client, account, sessions, room_id,
                         intent = "voice", store_dir = NULL, connect = TRUE,
                         service_url = NULL) {
    mx_require_crypto()
    call <- new.env(parent = emptyenv())
    call$client <- client
    call$account <- account
    call$sessions <- sessions
    call$store_dir <- store_dir
    call$room_id <- room_id
    call$intent <- intent
    call$identity <- mx_call_identity(client$user_id, client$device_id)
    call$keys <- mx_call_keys_new()
    call$session <- NULL
    call$members <- list()
    class(call) <- "mx_call"

    s <- mx_client_session(client)
    members <- mx_call_members(mx.api::mx_room_state(s, room_id))
    call$service_url <- service_url %||% mx_call_service_url(client, members)
    openid <- mx.api::mx_openid_token(s)
    call$token <- mx.api::mx_rtc_livekit_token(call$service_url, room_id,
        openid, client$device_id)
    mx_call_send_membership(call)
    mx_call_update_keys(call, members)
    if (connect) {
        mx_call_connect(call)
    }
    call
}

#' Join the LiveKit room of a call
#'
#' Connects the media side of a call made with \code{mx_call_join(connect
#' = FALSE)}: joins the LiveKit room with the media token, with
#' end-to-end encryption configured as Element Call and FluffyChat
#' expect (per-participant HKDF keys, a 256-slot key ring), and sets our
#' key and every peer key received so far.
#'
#' @param call An \code{"mx_call"}.
#' @param ... Further arguments to \code{livekitr::lk_connect()}, such
#'   as \code{opts}.
#' @return \code{call}, invisibly.
#' @export
mx_call_connect <- function(call, ...) {
    mx_require_livekitr()
    if (!is.null(call$session)) {
        return(invisible(call))
    }
    call$session <- livekitr::lk_connect(call$token$url, call$token$jwt,
        e2ee = mx_call_e2ee_options(), ...)
    if (!identical(call$session$identity, call$identity)) {
        warning("the LiveKit identity ", call$session$identity,
                " differs from the Matrix identity ", call$identity,
                "; other clients will not match this device's keys",
                call. = FALSE)
    }
    livekitr::lk_set_e2ee_key(call$session, call$keys$key,
                              identity = call$identity,
                              key_index = call$keys$index)
    for (identity in names(call$keys$peers)) {
        peer <- call$keys$peers[[identity]]
        livekitr::lk_set_e2ee_key(call$session, peer$key, identity = identity,
                                  key_index = peer$index)
    }
    invisible(call)
}

# How Element Call and FluffyChat configure the frame cryptor: keys are
# used as given (HKDF, not the shared-key PBKDF2 path), one slot per key
# index, and a few failed frames are tolerated while keys are in flight.
mx_call_e2ee_options <- function() {
    list(kdf = "hkdf", key_ring_size = 256L, ratchet_window_size = 10L,
         failure_tolerance = 10L)
}

#' Feed a sync response to a call
#'
#' Applies what a \code{/sync} response means for the call: peers' media
#' keys from the decrypted to-device events, membership changes (which
#' may rotate and resend our key), and the hourly refresh of our own
#' membership. Call it with every sync while in the call. When the
#' application already runs \code{\link{mx_crypto_process_sync}} on the
#' response, pass its result as \code{processed} so to-device events
#' are not decrypted twice.
#'
#' @param call An \code{"mx_call"}.
#' @param sync A parsed \code{/sync} response.
#' @param processed The result of \code{mx_crypto_process_sync()} on
#'   \code{sync}, or NULL to have it run here (its \code{sessions} are
#'   then kept in \code{call$sessions}).
#' @return A list of what changed: \code{keys}, the identities whose
#'   keys were received, and \code{members}, the current members when
#'   membership changed (NULL otherwise).
#' @export
mx_call_handle <- function(call, sync, processed = NULL) {
    if (is.null(processed)) {
        identity <- mx.crypto::mxc_account_identity_keys(call$account)
        processed <- mx_crypto_process_sync(call$account, call$sessions,
            sync, identity$curve25519, self_id = call$client$user_id,
            self_device_id = call$client$device_id)
        call$sessions <- processed$sessions
    }
    received <- character()
    # Call keys arrive two ways: Element Call sends them to-device, while
    # FluffyChat / matrix-dart-sdk sends them as an encrypted ROOM event
    # (surfaced in processed$events with its type and content). Read both.
    key_events <- c(processed$to_device %||% list(),
                    Filter(function(ev) identical(ev$room_id, call$room_id),
                           processed$events %||% list()))
    for (ev in key_events) {
        for (parsed in mx_call_key_parse(ev, call$room_id)) {
            mx_call_apply_peer_key(call, parsed)
            received <- c(received, parsed$identity)
        }
    }
    members <- NULL
    room <- sync$rooms$join[[call$room_id]]
    changed <- any(vapply(c(room$state$events %||% list(),
                            room$timeline$events %||% list()),
                          function(ev) identical(ev$type, MX_CALL_MEMBER),
                          logical(1)))
    now <- Sys.time()
    if (changed) {
        members <- mx_call_members(
                                   mx.api::mx_room_state(mx_client_session(call$client),
                call$room_id), now)
        mx_call_update_keys(call, members, now)
    }
    if (as.numeric(difftime(now, call$membership_sent, units = "secs")) >=
        MX_CALL_REFRESH_S) {
        mx_call_send_membership(call, now)
    }
    list(keys = received, members = members)
}

#' Poll the media of a call, then sync once
#'
#' One iteration of a call loop for programs with no sync loop of their
#' own: polls the LiveKit session with \code{livekitr::lk_poll()}, which
#' is where audio callbacks run, for up to \code{media_timeout} seconds
#' (it returns as soon as media events arrive, so the wait is short while
#' someone speaks), then syncs with \code{\link{mx_sync_update}} and
#' applies the response with \code{\link{mx_call_handle}}.
#'
#' Audio callbacks only run while this process polls, so the sync must
#' not block for long: the default \code{timeout = 0} asks the homeserver
#' to answer at once. Not every homeserver complies: Tuwunel 1.9 holds an
#' incremental sync that has nothing new for 5 s whatever the timeout,
#' and returns at once only when something happened. Frames that arrive
#' meanwhile wait in \pkg{livekitr}'s native queue, so nothing is lost,
#' but they reach the callback late. A program that needs prompt audio
#' on such a server should sync from another process or thread.
#'
#' @param call An \code{"mx_call"}.
#' @param media_timeout Seconds to wait in the media poll.
#' @param timeout Seconds to let the sync long poll wait.
#' @return The LiveKit events from \code{livekitr::lk_poll()}, or an
#'   empty list when the call has no media session.
#' @export
mx_call_poll <- function(call, media_timeout = 0.5, timeout = 0) {
    events <- if (is.null(call$session)) {
        list()
    } else {
        livekitr::lk_poll(call$session, timeout = media_timeout)
    }
    res <- mx_sync_update(call$client, timeout = as.integer(timeout * 1000),
                          save = !is.null(attr(call$client, "path")))
    call$client <- res$client
    mx_call_handle(call, res$sync)
    events
}

#' Leave a MatrixRTC call
#'
#' Leaves the LiveKit room and clears this device's membership event.
#'
#' @param call An \code{"mx_call"}.
#' @return \code{NULL}, invisibly.
#' @export
mx_call_leave <- function(call) {
    if (!is.null(call$session)) {
        livekitr::lk_disconnect(call$session)
        call$session <- NULL
    }
    # An empty content object is how a device leaves; the state key stays.
    mx.api::mx_set_state(mx_client_session(call$client), call$room_id,
                         MX_CALL_MEMBER, stats::setNames(list(), character()),
                         mx_call_state_key(call$client$user_id, call$client$device_id))
    invisible(NULL)
}

#' @export
print.mx_call <- function(x, ...) {
    cat("<mx_call> room ", x$room_id, " as ", x$identity,
        if (is.null(x$session)) " (media not connected)" else " (connected)",
        "\n", sep = "")
    cat("  JWT service: ", x$service_url, "\n", sep = "")
    cat("  members in call: ", length(x$members), ", key index: ",
        x$keys$index, ", peer keys: ", length(x$keys$peers), "\n", sep = "")
    invisible(x)
}
