# Session construction and first-time login.

#' Build an mx.api session from a client config
#'
#' @param client Named list or \code{"mx_client_config"} with \code{server},
#'   \code{token}, \code{user_id}, and \code{device_id}.
#' @return An \code{"mx_session"} from \pkg{mx.api}.
#' @export
mx_client_session <- function(client) {
    required <- c("server", "token", "user_id", "device_id")
    missing <- required[!vapply(required, function(x) {
        !is.null(client[[x]]) && length(client[[x]]) == 1L &&
        nzchar(client[[x]])
    }, logical(1))]
    if (length(missing)) {
        stop("client config missing fields: ",
             paste(missing, collapse = ", "), call. = FALSE)
    }
    mx.api::mx_session(
                       server = client$server,
                       token = client$token,
                       user_id = client$user_id,
                       device_id = client$device_id
    )
}

#' Configure and save a Matrix client
#'
#' Logs in with \pkg{mx.api}, joins or records the target room, and writes
#' a reusable local config. Extra fields are merged into the saved config
#' so applications can persist their own defaults without reimplementing
#' login.
#'
#' @param server Character. Homeserver base URL.
#' @param user Character. Matrix user localpart or full MXID.
#' @param password Character. Account password.
#' @param room Character. Room ID or alias to join.
#' @param app Character. Application namespace.
#' @param path Character or NULL. Explicit destination path.
#' @param device_id Character or NULL. Existing device id to reuse.
#' @param extra Named list. Additional fields to save.
#' @return Saved \code{"mx_client_config"}, invisibly.
#' @export
mx_client_configure <- function(server, user, password, room,
                                app = "mx.client", path = NULL,
                                device_id = NULL, extra = list()) {
    if (!is.list(extra) || is.null(names(extra)) && length(extra)) {
        stop("extra must be a named list", call. = FALSE)
    }
    s <- mx.api::mx_login(server, user, password, device_id = device_id)
    room_id <- mx.api::mx_room_join(s, room)
    cfg <- list(server = server, user = user, password = password,
                token = s$token, user_id = s$user_id,
                device_id = s$device_id, room_id = room_id, sync_token = NULL)
    if (length(extra)) {
        cfg <- utils::modifyList(cfg, extra)
    }
    out <- mx_client_from_config(cfg, path = path, app = app)
    mx_client_save(out, app = app, path = path)
}

#' Re-login with stored credentials and refresh the saved token
#'
#' Uses the password persisted in the client config to obtain a fresh
#' access token for the \emph{same} device (reusing
#' \code{client$device_id}, so an E2EE device identity survives the
#' refresh), then saves the updated config. Typical use is recovering
#' from an invalidated token; see \code{\link{mx_with_relogin}} for the
#' catch-and-retry wrapper.
#'
#' @param client Matrix client config with \code{password}.
#' @param save Logical. Persist the refreshed config (default TRUE).
#' @return The refreshed \code{"mx_client_config"}.
#' @export
mx_client_relogin <- function(client, save = TRUE) {
    if (is.null(client$password) || !nzchar(client$password)) {
        stop("client config has no stored password to re-login with",
             call. = FALSE)
    }
    s <- mx.api::mx_login(client$server, client$user, client$password,
                          device_id = client$device_id)
    refreshed <- mx_client_from_config(
                                       utils::modifyList(
            mx_client_plain_list(client),
            list(token = s$token, user_id = s$user_id, device_id = s$device_id)
        ),
                                       path = attr(client, "path"),
                                       app = attr(client, "app")
    )
    if (isTRUE(save)) {
        refreshed <- mx_client_save(refreshed)
    }
    refreshed
}

#' Run a client operation, re-logging in once on an expired token
#'
#' Calls \code{fn(client)}; if it fails with the server's invalid-token
#' error (\code{M_UNKNOWN_TOKEN}, signalled as a classed condition by
#' mx.api >= 0.3.0), re-logs in via \code{\link{mx_client_relogin}} and
#' retries once with the refreshed client. Any other error propagates.
#'
#' @param client Matrix client config with \code{password}.
#' @param fn Function taking a client config.
#' @param save Logical. Persist the refreshed config on relogin.
#' @return \code{fn}'s return value.
#' @examples
#' \dontrun{
#' mx_with_relogin(client, function(cl) {
#'     mx_send_text(cl, "still here after a token rotation")
#' })
#' }
#' @export
mx_with_relogin <- function(client, fn, save = TRUE) {
    tryCatch(
             fn(client),
             mx_error_M_UNKNOWN_TOKEN = function(e) {
        message("mx.client: token rejected; re-logging in")
        fn(mx_client_relogin(client, save = save))
    }
    )
}

