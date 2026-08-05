# --- Config paths and persistence ---

tmp <- tempfile("mx-client-test-")
dir.create(tmp, recursive = TRUE)
cfg_path <- file.path(tmp, "matrix.json")
legacy_path <- file.path(tmp, "legacy.json")
old_env <- Sys.getenv("MX_CLIENT_TEST_MATRIX_CONFIG", NA_character_)
Sys.setenv(MX_CLIENT_TEST_MATRIX_CONFIG = cfg_path)

cfg <- mx.client::mx_client_from_config(
    list(server = "https://matrix.example", token = "tok",
         user_id = "@bot:example", device_id = "DEV", room_id = "!room:ex"),
    app = "mx.client.test"
)
saved <- mx.client::mx_client_save(cfg, app = "mx.client.test")
expect_equal(attr(saved, "path"), cfg_path)
expect_true(file.exists(cfg_path))
loaded <- mx.client::mx_client_load(app = "mx.client.test")
expect_equal(loaded$user_id, "@bot:example")
expect_inherits(loaded, "mx_client_config")

Sys.unsetenv("MX_CLIENT_TEST_MATRIX_CONFIG")
writeLines(jsonlite::toJSON(list(server = "s", token = "t",
                                 user_id = "@u:s", device_id = "D",
                                 room_id = "!r:s"),
                            auto_unbox = TRUE), legacy_path)
loaded_legacy <- mx.client::mx_client_load(
    app = "mx.client.test",
    legacy_path = legacy_path
)
expect_equal(loaded_legacy$room_id, "!r:s")

# --- Session validation ---

sess <- mx.client::mx_client_session(loaded)
expect_inherits(sess, "mx_session")
expect_error(mx.client::mx_client_session(list(server = "s")),
             pattern = "missing fields")

# --- Room resolution without network ---

expect_equal(mx.client::mx_resolve_room(loaded, NULL), "!room:ex")
expect_equal(mx.client::mx_resolve_room(loaded, "!literal:ex"), "!literal:ex")
resolved <- mx.client::mx_resolve_room(
    loaded, "Ops", room_cache = list(Ops = "!ops:ex"), details = TRUE
)
expect_equal(resolved$room_id, "!ops:ex")
expect_equal(resolved$source, "cache")

# --- Sync response extraction ---

sync <- list(rooms = list(join = list(
    "!r:ex" = list(timeline = list(events = list(
        list(type = "m.room.message", sender = "@alice:ex",
             event_id = "$1",
             content = list(msgtype = "m.text", body = "hello",
                            `m.mentions` = list(user_ids = list("@bot:ex")))),
        list(type = "m.room.message", sender = "@bot:ex",
             event_id = "$2",
             content = list(msgtype = "m.text", body = "self")),
        list(type = "m.room.message", sender = "@alice:ex",
             event_id = "$3",
             content = list(msgtype = "m.image", body = "skip"))
    )))
)))
events <- mx.client::mx_extract_text_events(sync, "@bot:ex")
expect_equal(length(events), 2L)
expect_false(events[[1]]$is_self)
expect_true(events[[2]]$is_self)
expect_equal(events[[1]]$mentions[[1]], "@bot:ex")

# origin_server_ts survives extraction. Consumers that stamp messages
# with the poll's wall clock instead reorder history on every restart,
# so a record without it is not merely lossy.
ts_sync <- list(rooms = list(join = list("!r:ex" = list(timeline = list(
    events = list(
        list(type = "m.room.message", sender = "@alice:ex", event_id = "$1",
             origin_server_ts = 1700000000000,
             content = list(msgtype = "m.text", body = "stamped")),
        list(type = "m.room.message", sender = "@alice:ex", event_id = "$2",
             content = list(msgtype = "m.text", body = "unstamped"))
    )
)))))
ts_events <- mx.client::mx_extract_text_events(ts_sync, "@bot:ex")
expect_equal(ts_events[[1]]$ts, 1700000000000)
# A server that omits it yields NULL rather than a fabricated time
expect_null(ts_events[[2]]$ts)

invites <- mx.client::mx_extract_invites(list(rooms = list(invite = list(
    "!a:ex" = list(), "!b:ex" = list()
))))
expect_equal(invites, c("!a:ex", "!b:ex"))
expect_equal(mx.client::mx_extract_invites(list(rooms = list(join = list()))),
             character())

# --- Reaction verdict extraction ---

reaction_sync <- list(rooms = list(join = list(
    "!r:ex" = list(timeline = list(events = list(
        list(type = "m.reaction", sender = "@bot:ex",
             content = list(`m.relates_to` = list(event_id = "$target",
                                                  key = "\U0001F44D"))),
        list(type = "m.reaction", sender = "@alice:ex",
             content = list(`m.relates_to` = list(event_id = "$target",
                                                  key = "\U0001F44D")))
    )))
)))
expect_true(mx.client::mx_extract_reaction_verdict(
    reaction_sync, "!r:ex", "@bot:ex", "$target"
))
expect_null(mx.client::mx_extract_reaction_verdict(
    reaction_sync, "!missing:ex", "@bot:ex", "$target"
))

# --- Message relations survive extraction ---
# m.relates_to is what tells a threaded reply from a rich reply from an
# edit. Dropping it left every caller unable to tell any of them from an
# ordinary message.

rel_sync <- list(rooms = list(join = list("!r:ex" = list(timeline = list(
    events = list(
        list(type = "m.room.message", event_id = "$plain", sender = "@a:ex",
             content = list(msgtype = "m.text", body = "hello")),
        list(type = "m.room.message", event_id = "$thread", sender = "@a:ex",
             content = list(msgtype = "m.text", body = "in a thread",
                            `m.relates_to` = list(rel_type = "m.thread",
                                                  event_id = "$root"))),
        list(type = "m.room.message", event_id = "$reply", sender = "@a:ex",
             content = list(msgtype = "m.text", body = "a rich reply",
                            `m.relates_to` = list(
                                `m.in_reply_to` = list(event_id = "$orig"))))
    ))))))
rel <- mx.client::mx_extract_text_events(rel_sync, "@bot:ex")
expect_equal(length(rel), 3L)
# An ordinary message has no relation, and NULL is the answer -- not an
# empty list a caller has to test the shape of.
expect_null(rel[[1]]$relates_to)
# A thread carries its rel_type and root.
expect_equal(rel[[2]]$relates_to$rel_type, "m.thread")
expect_equal(rel[[2]]$relates_to$event_id, "$root")
# A rich reply has no rel_type at all, which is exactly how it differs
# from a thread. Passed through verbatim rather than normalized, so the
# caller can tell.
expect_null(rel[[3]]$relates_to$rel_type)
expect_equal(rel[[3]]$relates_to$`m.in_reply_to`$event_id, "$orig")
# The fields that were already there are unchanged.
expect_equal(rel[[2]]$body, "in a thread")
expect_equal(rel[[2]]$event_id, "$thread")

# --- General reaction extraction ---
# mx_extract_reaction_verdict() answers one approve/deny question about
# one event, with the key semantics baked in. This reports every reaction
# and leaves what the keys mean to the caller.

rx_sync <- list(rooms = list(join = list(
    "!r:ex" = list(timeline = list(events = list(
        list(type = "m.reaction", event_id = "$r1", sender = "@alice:ex",
             origin_server_ts = 1700000000000,
             content = list(`m.relates_to` = list(rel_type = "m.annotation",
                                                  event_id = "$msg",
                                                  key = "\U0001F44D"))),
        list(type = "m.reaction", event_id = "$r2", sender = "@bot:ex",
             content = list(`m.relates_to` = list(rel_type = "m.annotation",
                                                  event_id = "$msg",
                                                  key = "eyes"))),
        # An ordinary message in the same timeline is not a reaction.
        list(type = "m.room.message", event_id = "$m1", sender = "@alice:ex",
             content = list(msgtype = "m.text", body = "hello"))
    ))),
    "!other:ex" = list(timeline = list(events = list(
        list(type = "m.reaction", event_id = "$r3", sender = "@carol:ex",
             content = list(`m.relates_to` = list(rel_type = "m.annotation",
                                                  event_id = "$elsewhere",
                                                  key = "x")))
    )))
)))

rx <- mx.client::mx_extract_reactions(rx_sync, "@bot:ex")
expect_equal(length(rx), 3L)
# Every room is walked, not just the first.
expect_equal(sort(vapply(rx, function(r) r$room_id, "")),
             c("!other:ex", "!r:ex", "!r:ex"))
# event_id is the reaction's own, and the annotated event is separate --
# conflating them is the mistake this record shape exists to prevent.
expect_equal(rx[[1]]$event_id, "$r1")
expect_equal(rx[[1]]$target_event_id, "$msg")
expect_equal(rx[[1]]$sender, "@alice:ex")
expect_equal(rx[[1]]$key, "\U0001F44D")
expect_equal(rx[[1]]$ts, 1700000000000)
# Self reactions are kept and tagged, like self messages: a consumer
# tracking which reactions it has already placed needs them.
expect_false(rx[[1]]$is_self)
expect_true(rx[[2]]$is_self)
expect_equal(rx[[2]]$key, "eyes")
# A server that omits origin_server_ts leaves ts NULL rather than
# inventing one.
expect_null(rx[[2]]$ts)

# An m.reaction that annotates nothing is not a reaction to anything.
malformed <- list(rooms = list(join = list("!r:ex" = list(timeline = list(
    events = list(
        # no m.relates_to at all
        list(type = "m.reaction", event_id = "$a", sender = "@alice:ex",
             content = list()),
        # a relation that is not an annotation
        list(type = "m.reaction", event_id = "$b", sender = "@alice:ex",
             content = list(`m.relates_to` = list(rel_type = "m.thread",
                                                  event_id = "$msg",
                                                  key = "x"))),
        # annotation with no target
        list(type = "m.reaction", event_id = "$c", sender = "@alice:ex",
             content = list(`m.relates_to` = list(rel_type = "m.annotation",
                                                  key = "x"))),
        # annotation with no key
        list(type = "m.reaction", event_id = "$d", sender = "@alice:ex",
             content = list(`m.relates_to` = list(rel_type = "m.annotation",
                                                  event_id = "$msg")))
    ))))))
expect_equal(length(mx.client::mx_extract_reactions(malformed, "@bot:ex")), 0L)

# Empty and message-only syncs return an empty list, not an error.
expect_equal(length(mx.client::mx_extract_reactions(list(), "@bot:ex")), 0L)
expect_equal(length(mx.client::mx_extract_reactions(
    list(rooms = list(join = list())), "@bot:ex")), 0L)
expect_equal(length(mx.client::mx_extract_reactions(
    list(rooms = list(join = list("!r:ex" = list(timeline = list(
        events = list(list(type = "m.room.message", event_id = "$m",
                           sender = "@a:ex",
                           content = list(msgtype = "m.text",
                                          body = "hi")))))))),
    "@bot:ex")), 0L)

if (is.na(old_env)) {
    Sys.unsetenv("MX_CLIENT_TEST_MATRIX_CONFIG")
} else {
    Sys.setenv(MX_CLIENT_TEST_MATRIX_CONFIG = old_env)
}
unlink(tmp, recursive = TRUE)

# mx_room_encrypted: signature (network behavior is live-validated)
expect_true(is.function(mx.client::mx_room_encrypted))
expect_equal(names(formals(mx.client::mx_room_encrypted)),
             c("client", "room", "room_cache"))

# --- print.mx_client_config masks credentials ---

secret_cfg <- mx.client::mx_client_from_config(
    list(server = "https://matrix.example", token = "syt_supersecret",
         password = "hunter2", user_id = "@bot:example", device_id = "DEV",
         room_id = "!room:ex", sync_token = "s99_cursor",
         tools_filter = list()),
    path = "/tmp/matrix.json"
)
out <- paste(capture.output(print(secret_cfg)), collapse = "\n")
# credentials never appear, in any form
expect_false(grepl("syt_supersecret", out, fixed = TRUE))
expect_false(grepl("hunter2", out, fixed = TRUE))
expect_true(grepl("token:\\s+<hidden>", out))
expect_true(grepl("password:\\s+<hidden>", out))
# non-secret fields stay visible, including the sync cursor
expect_true(grepl("@bot:example", out, fixed = TRUE))
expect_true(grepl("s99_cursor", out, fixed = TRUE))
expect_true(grepl("/tmp/matrix.json", out, fixed = TRUE))
# an empty credential reads as unset rather than hidden
empty_cfg <- mx.client::mx_client_from_config(
    list(server = "https://matrix.example", token = "", user_id = "@b:e")
)
out_empty <- paste(capture.output(print(empty_cfg)), collapse = "\n")
expect_true(grepl("token:\\s+<unset>", out_empty))
# printing returns the object unchanged, and invisibly
capture.output(vis <- withVisible(print(secret_cfg)))
expect_false(vis$visible)
expect_identical(vis$value, secret_cfg)
