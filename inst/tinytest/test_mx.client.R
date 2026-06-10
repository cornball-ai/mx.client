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
