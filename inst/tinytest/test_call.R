# MatrixRTC call layer: membership events, key events, the rotation
# policy and service discovery. No homeserver and no LiveKit: HTTP is
# replaced below where a function reaches for it.

library(tinytest)
library(mx.client)

ns <- asNamespace("mx.client")
ROOM <- "!call:example.org"
T0 <- as.POSIXct(1.7e9, origin = "1970-01-01", tz = "UTC")

with_api <- function(name, handler, code) {
    api <- asNamespace("mx.api")
    original <- get(name, envir = api, inherits = FALSE)
    assignInNamespace(name, handler, ns = "mx.api")
    on.exit(assignInNamespace(name, original, ns = "mx.api"), add = TRUE)
    force(code)
}

client <- list(server = "https://example.org", token = "t",
               user_id = "@bot:example.org", device_id = "BOTDEV")

# ---- identity and membership content ---------------------------------

expect_identical(ns$mx_call_identity("@a:ex", "D"), "@a:ex:D")
expect_identical(ns$mx_call_state_key("@a:ex", "D"), "_@a:ex_D_m.call")

content <- ns$mx_call_member_content("@bot:example.org", "BOTDEV",
                                     "https://jwt.example.org", ROOM, now = T0)
expect_identical(content$application, "m.call")
expect_identical(content$call_id, "")
expect_identical(content$scope, "m.room")
expect_identical(content$device_id, "BOTDEV")
expect_identical(content$membershipID, "@bot:example.org:BOTDEV")
expect_equal(content$expires, 4 * 3600 * 1000)
expect_identical(content$`m.call.intent`, "voice")
expect_identical(content$focus_active$type, "livekit")
expect_identical(content$foci_preferred[[1]]$livekit_service_url,
                 "https://jwt.example.org")
expect_identical(content$foci_preferred[[1]]$livekit_alias, ROOM)
expect_equal(content$created_ts, 1.7e12)
expect_equal(content$created_at, 1.7e12)
expect_error(ns$mx_call_member_content("@a:ex", "D", "u", ROOM, intent = "x"))
# It survives JSON as the clients read it: expires and timestamps as numbers
js <- jsonlite::fromJSON(jsonlite::toJSON(content, auto_unbox = TRUE,
                                          digits = NA), simplifyVector = FALSE)
expect_equal(js$created_ts, 1.7e12)
expect_equal(js$expires, 14400000)

# ---- reading memberships from room state -----------------------------

member_event <- function(sender, device, created, expires = NULL,
                         focus = "livekit", content_extra = list(),
                         origin_ts = NULL) {
    c <- list(application = "m.call", device_id = device,
              focus_active = list(type = focus),
              foci_preferred = list(list(type = "livekit",
                                         livekit_service_url = "https://jwt.a")))
    if (!is.null(created)) c$created_ts <- created
    if (!is.null(expires)) c$expires <- expires
    c <- c(c, content_extra)
    ev <- list(type = "org.matrix.msc3401.call.member", sender = sender,
               state_key = ns$mx_call_state_key(sender, device), content = c)
    if (!is.null(origin_ts)) ev$origin_server_ts <- origin_ts
    ev
}
now_ms <- ns$mx_call_now_ms(T0)
state <- list(
    member_event("@alice:example.org", "PHONE", now_ms - 1000),
    member_event("@carol:example.org", "OLD", now_ms - 5 * 3600 * 1000),
    member_event("@dave:example.org", "SHORT", now_ms - 2000, expires = 1000),
    list(type = "org.matrix.msc3401.call.member", sender = "@erin:example.org",
         state_key = "_@erin:example.org_GONE_m.call",
         content = stats::setNames(list(), character())),
    member_event("@frank:example.org", "JITSI", now_ms, focus = "jitsi"),
    member_event("@bob:example.org", "LAPTOP", NULL, origin_ts = now_ms - 60000,
                 content_extra = list(membershipID = "custom")),
    list(type = "m.room.member", sender = "@alice:example.org",
         state_key = "@alice:example.org", content = list(membership = "join"))
)
members <- mx_call_members(state, now = T0)
expect_equal(length(members), 2L)
expect_identical(vapply(members, `[[`, "", "identity"),
                 c("@alice:example.org:PHONE", "@bob:example.org:LAPTOP"))
expect_identical(members[[1]]$service_urls, "https://jwt.a")
expect_identical(members[[1]]$membership_id, "@alice:example.org:PHONE")
expect_identical(members[[2]]$membership_id, "custom")
expect_equal(members[[2]]$expires_at, now_ms - 60000 + 4 * 3600 * 1000)
expect_equal(length(mx_call_members(list(), now = T0)), 0L)
# created_at (FluffyChat's name) is read too
fc <- member_event("@g:ex", "FC", NULL)
fc$content$created_at <- now_ms
expect_equal(length(mx_call_members(list(fc), now = T0)), 1L)

# ---- service discovery ------------------------------------------------

expect_identical(mx_call_service_url(client, members), "https://jwt.a")
transports <- list(list(type = "livekit",
                        livekit_service_url = "https://jwt.transport"))
expect_identical(
    with_api("mx_rtc_transports", function(session) transports,
             mx_call_service_url(client, list())),
    "https://jwt.transport")
expect_identical(
    with_api("mx_rtc_transports", function(session) list(),
             with_api("mx_well_known_client", function(server_name) {
                 expect_identical(server_name, "example.org")
                 list(`org.matrix.msc4143.rtc_foci` = list(list(
                     type = "livekit",
                     livekit_service_url = "https://jwt.wellknown")))
             }, mx_call_service_url(client, list()))),
    "https://jwt.wellknown")
expect_error(
    with_api("mx_rtc_transports", function(session) list(),
             with_api("mx_well_known_client", function(server_name) NULL,
                      mx_call_service_url(client, list()))),
    "no LiveKit JWT service found")

# ---- key events -------------------------------------------------------

key <- as.raw(0:15)
kc <- ns$mx_call_key_content(key, 3L, "@bot:example.org", "BOTDEV", ROOM,
                             now = T0)
# keys is an ARRAY of {index, key} (MSC + Element/FluffyChat wire shape).
expect_true(is.null(names(kc$keys)))
expect_identical(length(kc$keys), 1L)
expect_identical(kc$keys[[1]]$index, 3L)
expect_identical(kc$keys[[1]]$key, "AAECAwQFBgcICQoLDA0ODw==")
# Superset content: FluffyChat's top-level device_id/call_id AND Element's
# member block, so one object serves both transports.
expect_identical(kc$device_id, "BOTDEV")
expect_identical(kc$call_id, "")
expect_identical(kc$member$id, "@bot:example.org:BOTDEV")
expect_identical(kc$member$claimed_device_id, "BOTDEV")
expect_identical(kc$room_id, ROOM)
expect_identical(kc$session$application, "m.call")
expect_equal(kc$sent_ts, 1.7e12)
# It must serialize with keys as a JSON array of objects.
kc_json <- jsonlite::toJSON(kc, auto_unbox = TRUE)
expect_true(grepl('"keys":\\[\\{"index":3,"key":', kc_json))

# A FluffyChat room-event key: top-level device_id, no member, no room_id
# in content (the room is the event's own). Parsed with simplifyVector
# = FALSE as off the wire.
room_ev <- jsonlite::fromJSON(paste0(
    '{"type":"io.element.call.encryption_keys","sender":"@al:example.org",',
    '"room_id":"', ROOM, '","content":{"call_id":"","device_id":"PHONE",',
    '"keys":[{"index":2,"key":"AAECAwQFBgcICQoLDA0ODw"}],"sent_ts":1}}'),
    simplifyVector = FALSE)
rp <- mx_call_key_parse(room_ev, ROOM)
expect_identical(length(rp), 1L)
expect_identical(rp[[1]]$identity, "@al:example.org:PHONE")
expect_identical(rp[[1]]$index, 2L)
expect_identical(rp[[1]]$key, key)

# A spec-shaped event as it arrives off the wire: Olm plaintext is parsed
# with simplifyVector = FALSE, so keys is a list of lists. This is the
# exact shape that regressed in 0.2.1.1.
wire <- jsonlite::fromJSON(paste0(
    '{"type":"io.element.call.encryption_keys","sender":"@bot:example.org",',
    '"content":{"call_id":"","keys":[{"index":3,',
    '"key":"AAECAwQFBgcICQoLDA0ODw"}],',
    '"member":{"claimed_device_id":"BOTDEV","id":"@bot:example.org"},',
    '"room_id":"', ROOM, '","sent_ts":1}}'), simplifyVector = FALSE)
parsed <- mx_call_key_parse(wire, ROOM)
expect_identical(length(parsed), 1L)
expect_identical(parsed[[1]]$identity, "@bot:example.org:BOTDEV")
expect_identical(parsed[[1]]$key, key)
expect_identical(parsed[[1]]$index, 3L)

# Our own content round-trips through the parser.
rt <- mx_call_key_parse(list(type = "io.element.call.encryption_keys",
                             sender = "@bot:example.org", content = kc), ROOM)
expect_identical(length(rt), 1L)
expect_identical(rt[[1]]$key, key)
expect_identical(rt[[1]]$index, 3L)

# Several keys in one event: each becomes an entry.
multi <- list(type = "io.element.call.encryption_keys",
              sender = "@bot:example.org",
              content = list(room_id = ROOM,
                             member = list(claimed_device_id = "BOTDEV"),
                             keys = list(list(index = 0, key = "AAA="),
                                         list(index = 1, key = "AQE="))))
pm <- mx_call_key_parse(multi, ROOM)
expect_identical(length(pm), 2L)
expect_identical(vapply(pm, `[[`, 0L, "index"), c(0L, 1L))

# Tolerate a non-conformant sender that puts keys as a single object.
obj <- list(type = "io.element.call.encryption_keys",
            sender = "@bot:example.org",
            content = list(room_id = ROOM,
                           member = list(claimed_device_id = "BOTDEV"),
                           keys = list(index = 3, key = "AAECAwQFBgcICQoLDA0ODw")))
expect_identical(mx_call_key_parse(obj, ROOM)[[1]]$key, key)

# Unpadded and URL-safe base64 decode too.
kc3 <- kc
kc3$keys[[1]]$key <- jsonlite::base64url_enc(as.raw(c(0xfb, 0xff, 0xfe, 1)))
expect_identical(mx_call_key_parse(list(type = "io.element.call.encryption_keys",
    sender = "@bot:example.org", content = kc3), ROOM)[[1]]$key,
    as.raw(c(0xfb, 0xff, 0xfe, 1)))

# Rejections return an empty list: other room, other type, bad index,
# missing device.
expect_identical(mx_call_key_parse(list(type = "io.element.call.encryption_keys",
    sender = "@bot:example.org", content = kc), "!other:example.org"), list())
expect_identical(mx_call_key_parse(list(type = "m.room_key", sender = "@b:ex",
                                        content = kc), ROOM), list())
kc4 <- kc
kc4$keys[[1]]$index <- -1
expect_identical(mx_call_key_parse(list(type = "io.element.call.encryption_keys",
    sender = "@bot:example.org", content = kc4), ROOM), list())
# No device at all (neither member$claimed_device_id nor top-level
# device_id): unparseable.
kc5 <- kc
kc5$member$claimed_device_id <- NULL
kc5$device_id <- NULL
expect_identical(mx_call_key_parse(list(type = "io.element.call.encryption_keys",
    sender = "@bot:example.org", content = kc5), ROOM), list())
# member alone still works when device_id is absent (Element Call shape).
kc6 <- kc
kc6$device_id <- NULL
expect_identical(mx_call_key_parse(list(type = "io.element.call.encryption_keys",
    sender = "@bot:example.org", content = kc6), ROOM)[[1]]$identity,
    "@bot:example.org:BOTDEV")

# ---- rotation policy --------------------------------------------------

keys <- ns$mx_call_keys_new()
expect_identical(keys$index, -1L)
# No key yet: make one, send to everyone
plan <- mx_call_key_plan(keys, c("@a:ex:A", "@b:ex:B"), now = T0)
expect_true(plan$rotate)
expect_identical(plan$targets, c("@a:ex:A", "@b:ex:B"))
ns$mx_call_keys_rotate(keys, T0)
expect_identical(keys$index, 0L)
expect_equal(length(keys$key), 16L)
keys$shared_with <- c("@a:ex:A", "@b:ex:B")
# Same members: nothing to do
plan <- mx_call_key_plan(keys, c("@b:ex:B", "@a:ex:A"), now = T0 + 5)
expect_false(plan$rotate)
expect_identical(plan$targets, character())
# Joiner inside the grace period: current key to the joiner only
plan <- mx_call_key_plan(keys, c("@a:ex:A", "@b:ex:B", "@c:ex:C"), now = T0 + 5)
expect_false(plan$rotate)
expect_identical(plan$targets, "@c:ex:C")
# Joiner after the grace period: rotate, send to all
plan <- mx_call_key_plan(keys, c("@a:ex:A", "@b:ex:B", "@c:ex:C"), now = T0 + 30)
expect_true(plan$rotate)
expect_identical(plan$targets, c("@a:ex:A", "@b:ex:B", "@c:ex:C"))
# Leaver: rotate for the rest, even inside the grace period
plan <- mx_call_key_plan(keys, "@a:ex:A", now = T0 + 1)
expect_true(plan$rotate)
expect_identical(plan$targets, "@a:ex:A")
# Everyone left: rotate, nobody to send to
plan <- mx_call_key_plan(keys, character(), now = T0 + 1)
expect_true(plan$rotate)
expect_identical(plan$targets, character())
# Indexes wrap below 255
keys$index <- 254L
ns$mx_call_keys_rotate(keys, T0)
expect_identical(keys$index, 0L)
expect_identical(keys$shared_with, character())

# ---- update_keys drives send_key with the plan -----------------------

local({
    sends <- list()
    orig <- get("mx_call_send_key", envir = ns)
    assignInNamespace("mx_call_send_key", function(call, targets) {
        sends[[length(sends) + 1L]] <<- list(index = call$keys$index,
                                             targets = targets)
        call$keys$shared_with <- union(call$keys$shared_with, targets)
        invisible(NULL)
    }, ns = "mx.client")
    on.exit(assignInNamespace("mx_call_send_key", orig, ns = "mx.client"),
            add = TRUE)
    call <- new.env()
    call$identity <- "@bot:example.org:BOTDEV"
    call$keys <- ns$mx_call_keys_new()
    call$session <- NULL
    me <- list(identity = "@bot:example.org:BOTDEV")
    a <- list(identity = "@alice:example.org:PHONE")
    b <- list(identity = "@bob:example.org:LAPTOP")
    ns$mx_call_update_keys(call, list(me, a), now = T0)
    expect_identical(sends[[1]], list(index = 0L, targets = a$identity))
    ns$mx_call_update_keys(call, list(me, a, b), now = T0 + 2)
    expect_identical(sends[[2]], list(index = 0L, targets = b$identity))
    ns$mx_call_update_keys(call, list(me, b), now = T0 + 3)
    expect_identical(sends[[3]], list(index = 1L, targets = b$identity))
    expect_equal(length(call$members), 2L)
})

# ---- mx_call_handle: keys from to_device, membership changes ----------

local({
    applied <- list()
    orig_apply <- get("mx_call_apply_peer_key", envir = ns)
    orig_update <- get("mx_call_update_keys", envir = ns)
    assignInNamespace("mx_call_apply_peer_key", function(call, parsed) {
        applied[[length(applied) + 1L]] <<- parsed$identity
        call$keys$peers[[parsed$identity]] <- parsed[c("key", "index")]
    }, ns = "mx.client")
    assignInNamespace("mx_call_update_keys", function(call, members, now) {
        call$members <- members
    }, ns = "mx.client")
    on.exit({
        assignInNamespace("mx_call_apply_peer_key", orig_apply, ns = "mx.client")
        assignInNamespace("mx_call_update_keys", orig_update, ns = "mx.client")
    }, add = TRUE)

    call <- new.env()
    call$client <- client
    call$room_id <- ROOM
    call$identity <- "@bot:example.org:BOTDEV"
    call$keys <- ns$mx_call_keys_new()
    call$session <- NULL
    call$members <- list()
    call$membership_sent <- Sys.time()

    peer_key <- ns$mx_call_key_content(as.raw(1:16), 2L, "@alice:example.org",
                                       "PHONE", ROOM)
    other_room <- ns$mx_call_key_content(as.raw(1:16), 2L, "@alice:example.org",
                                         "PHONE", "!other:example.org")
    # A room-event key (FluffyChat): no content room_id, room is the
    # record's room_id; a non-call room event and a wrong-room key event
    # must be ignored.
    room_key <- list(type = "io.element.call.encryption_keys",
                     sender = "@bob:example.org", room_id = ROOM,
                     content = list(call_id = "", device_id = "LAPTOP",
                         keys = list(list(index = 4, key = "AAECAwQFBgcICQoLDA0ODw"))))
    processed <- list(
        to_device = list(
            list(type = "io.element.call.encryption_keys",
                 sender = "@alice:example.org", content = peer_key),
            list(type = "io.element.call.encryption_keys",
                 sender = "@alice:example.org", content = other_room),
            list(type = "org.example.other", sender = "@x:ex", content = list())),
        events = list(
            room_key,
            list(type = "m.room.message", sender = "@c:ex", room_id = ROOM,
                 content = list(body = "hi")),
            list(type = "io.element.call.encryption_keys", sender = "@d:ex",
                 room_id = "!elsewhere:example.org",
                 content = list(device_id = "X",
                     keys = list(list(index = 9, key = "AAA="))))))
    quiet <- list(rooms = list(join = list()))
    res <- mx_call_handle(call, quiet, processed)
    expect_identical(sort(res$keys),
                     c("@alice:example.org:PHONE", "@bob:example.org:LAPTOP"))
    expect_null(res$members)
    expect_identical(sort(unlist(applied)),
                     c("@alice:example.org:PHONE", "@bob:example.org:LAPTOP"))
    expect_identical(call$keys$peers[["@alice:example.org:PHONE"]]$index, 2L)
    expect_identical(call$keys$peers[["@bob:example.org:LAPTOP"]]$index, 4L)

    # A membership event in the room's timeline triggers a state refresh
    with_state <- list(rooms = list(join = stats::setNames(list(list(
        timeline = list(events = list(list(
            type = "org.matrix.msc3401.call.member",
            sender = "@alice:example.org"))))), ROOM)))
    res <- with_api("mx_room_state", function(session, room_id) {
        expect_identical(room_id, ROOM)
        list(member_event("@alice:example.org", "PHONE",
                          ns$mx_call_now_ms(Sys.time())))
    }, mx_call_handle(call, with_state, list(to_device = list())))
    expect_equal(length(res$members), 1L)
    expect_identical(call$members[[1]]$identity, "@alice:example.org:PHONE")

    # Membership is re-sent once an hour
    sent <- NULL
    call$membership_sent <- Sys.time() - 3601
    call$service_url <- "https://jwt.a"
    call$intent <- "voice"
    with_api("mx_set_state", function(session, room_id, event_type, content,
                                      state_key = "") {
        sent <<- list(type = event_type, state_key = state_key,
                      content = content)
        list(event_id = "$e")
    }, mx_call_handle(call, quiet, list(to_device = list())))
    expect_identical(sent$type, "org.matrix.msc3401.call.member")
    expect_identical(sent$state_key, "_@bot:example.org_BOTDEV_m.call")
    expect_identical(sent$content$device_id, "BOTDEV")
    expect_true(as.numeric(Sys.time()) - as.numeric(call$membership_sent) < 5)
})

# ---- mx_call_leave clears the membership -----------------------------

local({
    sent <- NULL
    call <- new.env()
    call$client <- client
    call$room_id <- ROOM
    call$session <- NULL
    with_api("mx_set_state", function(session, room_id, event_type, content,
                                      state_key = "") {
        sent <<- list(room_id = room_id, type = event_type, content = content,
                      state_key = state_key)
        list(event_id = "$e")
    }, mx_call_leave(call))
    expect_identical(sent$room_id, ROOM)
    expect_identical(sent$state_key, "_@bot:example.org_BOTDEV_m.call")
    expect_equal(length(sent$content), 0L)
    expect_identical(as.character(jsonlite::toJSON(sent$content,
                                                   auto_unbox = TRUE)), "{}")
})

# ---- mx_call_join on the Matrix side only ----------------------------

local({
    calls <- list()
    record <- function(what) {
        function(...) {
            calls[[length(calls) + 1L]] <<- what
            switch(what,
                   room_state = list(member_event("@alice:example.org", "PHONE",
                                                  ns$mx_call_now_ms(Sys.time()))),
                   openid = list(access_token = "oid", token_type = "Bearer",
                                 matrix_server_name = "example.org",
                                 expires_in = 3600L),
                   livekit_token = list(url = "wss://sfu.example.org",
                                        jwt = "jwt"),
                   set_state = list(event_id = "$e"))
        }
    }
    orig_send <- get("mx_call_send_key", envir = ns)
    orig_req <- get("mx_require_crypto", envir = ns)
    assignInNamespace("mx_call_send_key", function(call, targets) {
        calls[[length(calls) + 1L]] <<- paste("send_key", paste(targets,
                                                                collapse = ","))
        call$keys$shared_with <- targets
    }, ns = "mx.client")
    assignInNamespace("mx_require_crypto", function() invisible(TRUE),
                      ns = "mx.client")
    on.exit({
        assignInNamespace("mx_call_send_key", orig_send, ns = "mx.client")
        assignInNamespace("mx_require_crypto", orig_req, ns = "mx.client")
    }, add = TRUE)
    call <- with_api("mx_room_state", record("room_state"),
        with_api("mx_openid_token", record("openid"),
        with_api("mx_rtc_livekit_token", record("livekit_token"),
        with_api("mx_set_state", record("set_state"),
            mx_call_join(client, NULL, mx_crypto_sessions_new(), ROOM,
                         connect = FALSE)))))
    expect_inherits(call, "mx_call")
    expect_identical(calls, list("room_state", "openid", "livekit_token",
                                 "set_state",
                                 "send_key @alice:example.org:PHONE"))
    expect_identical(call$service_url, "https://jwt.a")
    expect_identical(call$token$url, "wss://sfu.example.org")
    expect_identical(call$identity, "@bot:example.org:BOTDEV")
    expect_equal(length(call$members), 1L)
    expect_identical(call$keys$index, 0L)
    expect_null(call$session)
    expect_stdout(print(call), "media not connected")
    # An explicit service URL skips discovery
    call2 <- with_api("mx_room_state", function(...) list(),
        with_api("mx_openid_token", record("openid"),
        with_api("mx_rtc_livekit_token", function(service_url, ...) {
            expect_identical(service_url, "https://jwt.explicit")
            list(url = "wss://x", jwt = "j")
        },
        with_api("mx_set_state", record("set_state"),
            mx_call_join(client, NULL, mx_crypto_sessions_new(), ROOM,
                         connect = FALSE, service_url = "https://jwt.explicit")))))
    expect_identical(call2$service_url, "https://jwt.explicit")
    expect_equal(length(call2$members), 0L)
})
