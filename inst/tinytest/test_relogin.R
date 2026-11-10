library(tinytest)
library(mx.client)

# Signatures
expect_equal(names(formals(mx_client_relogin)), c("client", "save"))
expect_equal(names(formals(mx_with_relogin)), c("client", "fn", "save"))
expect_equal(
  names(formals(mx.client::mx_send_media)),
  c("client", "path", "room", "body", "msgtype", "content_type",
    "info", "room_cache", "dry_run")
)

cl <- mx_client_from_config(list(server = "https://x", user = "bot",
                                 token = "t", user_id = "@bot:x",
                                 device_id = "DEV", room_id = "!r:x"))

# mx_with_relogin: success path never relogs
expect_equal(mx_with_relogin(cl, function(c) "ok"), "ok")

# unrelated errors propagate untouched
expect_error(mx_with_relogin(cl, function(c) stop("boom")), "boom")

# token error without a stored password -> clear failure from relogin
token_err <- function(c) {
  stop(structure(class = c("mx_error_M_UNKNOWN_TOKEN", "mx_error",
                           "error", "condition"),
                 list(message = "Matrix error [M_UNKNOWN_TOKEN]: x",
                      call = NULL)))
}
expect_error(mx_with_relogin(cl, token_err), "no stored password")

# mx_send_media dry-run resolves the default room and sends nothing
expect_message(
  out <- mx.client::mx_send_media(cl, "clip.mp4", dry_run = TRUE),
  "dry-run"
)
expect_null(out)

# mx_set_displayname: signature, validation, and relogin plumbing
expect_equal(names(formals(mx.client::mx_set_displayname)),
             c("client", "name", "save"))
expect_error(mx.client::mx_set_displayname(cl, ""), "non-empty")
expect_error(mx.client::mx_set_displayname(cl, c("a", "b")), "single")
expect_error(mx.client::mx_set_displayname(cl, NA_character_), "non-empty")

# mx_set_displayname returns the client it ended up using (#18): the same
# client when the token holds, the refreshed one after a relogin.
local({
  old_name <- mx.api::mx_set_displayname
  old_login <- mx.api::mx_login
  on.exit({
    assignInNamespace("mx_set_displayname", old_name, ns = "mx.api")
    assignInNamespace("mx_login", old_login, ns = "mx.api")
  })
  tokens <- character()
  assignInNamespace("mx_set_displayname", function(session, name) {
    tokens <<- c(tokens, session$token)
    if (identical(session$token, "t")) token_err(NULL)
    invisible(TRUE)
  }, ns = "mx.api")
  assignInNamespace("mx_login", function(server, user, password, device_id = NULL) {
    list(token = "fresh", user_id = "@bot:x", device_id = "DEV")
  }, ns = "mx.api")

  good <- mx_client_from_config(list(server = "https://x", user = "bot",
                                     token = "live", user_id = "@bot:x",
                                     device_id = "DEV", room_id = "!r:x"))
  out <- withVisible(mx.client::mx_set_displayname(good, "bot"))
  expect_false(out$visible)
  expect_equal(out$value$token, "live")

  stale <- mx_client_from_config(list(server = "https://x", user = "bot",
                                      password = "pw", token = "t",
                                      user_id = "@bot:x", device_id = "DEV",
                                      room_id = "!r:x"))
  expect_message(
    refreshed <- mx.client::mx_set_displayname(stale, "bot", save = FALSE),
    "re-logging in"
  )
  expect_equal(refreshed$token, "fresh")
  expect_equal(tokens, c("live", "t", "fresh"))
})
