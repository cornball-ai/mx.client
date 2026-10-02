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
mx_call_key_content <- function(key, index, user_id, device_id, room_id,
                                now = Sys.time()) {
    list(
         keys = list(index = as.integer(index), key = mx_call_b64(key)),
         member = list(id = mx_call_identity(user_id, device_id),
                       claimed_device_id = device_id),
         room_id = room_id,
         session = list(application = "m.call", call_id = "", scope = "m.room"),
         sent_ts = mx_call_now_ms(now)
    )
}

#' Read a call key event
#'
#' Parses a decrypted \code{io.element.call.encryption_keys} to-device
#' event (from the \code{to_device} list of
#' \code{\link{mx_crypto_process_sync}}) into the LiveKit identity it
#' belongs to and the key to set for it.
#'
#' @param event List with \code{type}, \code{content} and \code{sender}.
#' @param room_id The call's room; keys for other rooms are ignored.
#' @return \code{list(identity, key, index)}, with \code{key} a raw
#'   vector, or NULL when the event is not a usable key for this room.
#' @examples
#' ev <- list(type = "io.element.call.encryption_keys",
#'     sender = "@alice:example.org",
#'     content = list(keys = list(index = 3, key = "AAECAwQFBgcICQoLDA0ODw=="),
#'         member = list(claimed_device_id = "PHONE"), room_id = "!r:example.org"))
#' mx_call_key_parse(ev, "!r:example.org")
#' @export
mx_call_key_parse <- function(event, room_id) {
    if (!identical(event$type, MX_CALL_KEYS)) return(NULL)
    c <- event$content
    if (!identical(c$room_id, room_id)) return(NULL)
    device <- c$member$claimed_device_id
    index <- c$keys$index
    key <- c$keys$key
    if (!is.character(event$sender) || !is.character(device) ||
        !nzchar(device) || !is.numeric(index) || length(index) != 1L ||
        index < 0 || index != floor(index) || !is.character(key)) {
        return(NULL)
    }
    bytes <- tryCatch(mx_call_b64_decode(key), error = function(e) NULL)
    if (is.null(bytes) || !length(bytes)) return(NULL)
    list(identity = mx_call_identity(event$sender, device), key = bytes,
         index = as.integer(index))
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
    mx.api::mx_set_state(mx_client_session(call$client), call$room_id,
                         MX_CALL_MEMBER, content,
                         mx_call_state_key(call$client$user_id, call$client$device_id))
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
    for (ev in processed$to_device %||% list()) {
        parsed <- mx_call_key_parse(ev, call$room_id)
        if (!is.null(parsed)) {
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

#' Sync once and poll the media of a call
#'
#' One iteration of a call loop for programs with no sync loop of their
#' own: syncs with \code{\link{mx_sync_update}}, applies the response with
#' \code{\link{mx_call_handle}}, and polls the LiveKit session with
#' \code{livekitr::lk_poll()}, which is where audio callbacks run.
#'
#' @param call An \code{"mx_call"}.
#' @param timeout Seconds to wait for the sync long poll.
#' @param media_timeout Seconds to wait in the media poll.
#' @return The LiveKit events from \code{livekitr::lk_poll()}, or an
#'   empty list when the call has no media session.
#' @export
mx_call_poll <- function(call, timeout = 1, media_timeout = 0.1) {
    res <- mx_sync_update(call$client, timeout = as.integer(timeout * 1000),
                          save = !is.null(attr(call$client, "path")))
    call$client <- res$client
    mx_call_handle(call, res$sync)
    if (is.null(call$session)) {
        return(list())
    }
    livekitr::lk_poll(call$session, timeout = media_timeout)
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
