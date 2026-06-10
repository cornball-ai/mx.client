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
