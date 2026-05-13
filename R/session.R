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
        stop("client config missing fields: ", paste(missing, collapse = ", "),
             call. = FALSE)
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
    cfg <- list(
                server = server,
                user = user,
                password = password,
                token = s$token,
                user_id = s$user_id,
                device_id = s$device_id,
                room_id = room_id,
                sync_token = NULL
    )
    if (length(extra)) {
        cfg <- utils::modifyList(cfg, extra)
    }
    out <- mx_client_from_config(cfg, path = path, app = app)
    mx_client_save(out, app = app, path = path)
}

