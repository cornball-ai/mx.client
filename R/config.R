# Local Matrix client configuration.

`%||%` <- function(x, y) {
    if (is.null(x) || !length(x)) {
        y
    } else {
        x
    }
}

mx_client_envvar <- function(app) {
    app <- gsub("[^A-Za-z0-9]+", "_", app)
    paste0(toupper(app), "_MATRIX_CONFIG")
}

#' Path to a Matrix client config file
#'
#' Resolves the config path for an application that uses mx.client. The
#' default environment variable is derived from \code{app}; for example,
#' \code{app = "corteza"} honors \code{CORTEZA_MATRIX_CONFIG}.
#'
#' @param app Character. Application namespace for \code{tools::R_user_dir()}.
#' @param env_var Character or NULL. Override environment variable name.
#' @return Character path.
#' @examples
#' mx_client_config_path("myapp")
#' @export
mx_client_config_path <- function(app = "mx.client", env_var = NULL) {
    env_var <- env_var %||% mx_client_envvar(app)
    env <- Sys.getenv(env_var, "")
    if (nzchar(env)) {
        return(path.expand(env))
    }
    file.path(tools::R_user_dir(app, "config"), "matrix.json")
}

#' Legacy Matrix config path for an application
#'
#' Currently only \code{app = "corteza"} has a historical path:
#' \code{~/.corteza/matrix.json}.
#'
#' @param app Character. Application namespace.
#' @return Character path or NULL.
#' @examples
#' mx_client_legacy_config_path("corteza")
#' @export
mx_client_legacy_config_path <- function(app = "mx.client") {
    if (identical(app, "corteza")) {
        return(path.expand("~/.corteza/matrix.json"))
    }
    NULL
}

#' Wrap a list as an mx.client config
#'
#' @param cfg Named list.
#' @param path Character or NULL. Source/sink path for saves.
#' @param app Character or NULL. Application namespace.
#' @return An object of class \code{"mx_client_config"}.
#' @examples
#' cfg <- mx_client_from_config(list(server = "https://matrix.example.org",
#'                                   token = "syt_example",
#'                                   user_id = "@bot:example.org",
#'                                   device_id = "DEVICEID"))
#' class(cfg)
#' @export
mx_client_from_config <- function(cfg, path = NULL, app = NULL) {
    if (!is.list(cfg)) {
        stop("cfg must be a list", call. = FALSE)
    }
    structure(cfg, class = unique(c("mx_client_config", class(cfg))),
              path = path, app = app)
}

mx_client_plain_list <- function(client) {
    out <- unclass(client)
    attr(out, "path") <- NULL
    attr(out, "app") <- NULL
    out
}

# Config fields holding credentials. sync_token is deliberately absent:
# it is a cursor, not a secret, and seeing it is useful when debugging.
mx_client_secret_fields <- c("token", "access_token", "refresh_token",
                             "password")

mx_client_field_text <- function(name, value) {
    set <- length(value) > 0L &&
    !all(is.na(value)) &&
    (!is.character(value) || any(nzchar(value)))
    if (name %in% mx_client_secret_fields) {
        return(if (set) {
                "<hidden>"
            } else {
                "<unset>"
            })
    }
    if (!set) {
        return("<unset>")
    }
    if (is.list(value) || length(value) > 1L) {
        return(sprintf("<%s[%d]>", class(value)[1L], length(value)))
    }
    as.character(value)
}

#' Print a Matrix client config
#'
#' Prints the config field by field with credentials masked, so that an
#' interactive session, a screenshot, or a pasted bug report does not
#' leak the access token or password. Secret fields show whether they
#' are set (\code{<hidden>}) or empty (\code{<unset>}) without showing
#' the value. Use \code{unclass(x)} or \code{str(unclass(x))} when the
#' raw credentials are genuinely needed.
#'
#' @param x An \code{mx_client_config}, as returned by
#'   \code{mx_client_load()} or \code{mx_client_from_config()}.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @examples
#' cfg <- mx_client_from_config(list(server = "https://matrix.example.org",
#'                                   token = "syt_secret_value",
#'                                   user_id = "@bot:example.org",
#'                                   device_id = "DEVICEID"))
#' cfg
#' @export
print.mx_client_config <- function(x, ...) {
    cat("<mx_client_config>\n")
    fields <- names(x)
    labels <- c(paste0(fields, ":"), if (!is.null(attr(x, "path"))) "path:")
    if (!length(labels)) {
        cat("  (no fields)\n")
        return(invisible(x))
    }
    width <- max(nchar(labels))
    for (f in fields) {
        cat(sprintf("  %-*s %s\n", width, paste0(f, ":"),
                    mx_client_field_text(f, x[[f]])))
    }
    if (!is.null(attr(x, "path"))) {
        cat(sprintf("  %-*s %s\n", width, "path:", attr(x, "path")))
    }
    invisible(x)
}

#' Load a Matrix client config
#'
#' Reads a JSON config. If \code{path} or the derived environment variable
#' is explicit, that path is authoritative. Otherwise \code{legacy_path}
#' is used as a compatibility fallback when present.
#'
#' @param app Character. Application namespace.
#' @param path Character or NULL. Explicit config path.
#' @param legacy_path Character or NULL. Backward-compatible fallback path.
#' @param env_var Character or NULL. Override environment variable name.
#' @return An \code{"mx_client_config"} object.
#' @examples
#' path <- file.path(tempdir(), "matrix.json")
#' cfg <- mx_client_from_config(list(server = "https://matrix.example.org",
#'                                   token = "syt_example",
#'                                   user_id = "@bot:example.org",
#'                                   device_id = "DEVICEID"))
#' mx_client_save(cfg, path = path)
#' mx_client_load(path = path)$user_id
#' unlink(path)
#' @export
mx_client_load <- function(app = "mx.client", path = NULL,
                           legacy_path = mx_client_legacy_config_path(app),
                           env_var = NULL) {
    env_var <- env_var %||% mx_client_envvar(app)
    env <- Sys.getenv(env_var, "")
    explicit <- !is.null(path) || nzchar(env)
    if (is.null(path)) {
        path <- mx_client_config_path(app, env_var = env_var)
    } else {
        path <- path.expand(path)
    }

    legacy_path <- if (is.null(legacy_path)) {
        NULL
    } else {
        path.expand(legacy_path)
    }
    src <- if (file.exists(path)) {
        path
    } else if (!explicit && !is.null(legacy_path) && file.exists(legacy_path)) {
        legacy_path
    } else {
        stop("Matrix not configured. Create a config with mx_client_configure().",
             call. = FALSE)
    }
    cfg <- jsonlite::fromJSON(src, simplifyVector = TRUE)
    mx_client_from_config(cfg, path = src, app = app)
}

#' Save a Matrix client config
#'
#' Writes JSON with mode 0600.
#'
#' @param client Named list or \code{"mx_client_config"}.
#' @param app Character or NULL. Application namespace.
#' @param path Character or NULL. Destination path.
#' @return The saved config, invisibly.
#' @examples
#' path <- file.path(tempdir(), "matrix.json")
#' mx_client_save(list(server = "https://matrix.example.org",
#'                     token = "syt_example",
#'                     user_id = "@bot:example.org",
#'                     device_id = "DEVICEID"),
#'                path = path)
#' unlink(path)
#' @export
mx_client_save <- function(client, app = NULL, path = NULL) {
    app <- app %||% attr(client, "app") %||% "mx.client"
    path <- path %||% attr(client, "path") %||% mx_client_config_path(app)
    path <- path.expand(path)
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    cfg <- mx_client_plain_list(client)
    writeLines(jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE), path)
    Sys.chmod(path, mode = "0600")
    invisible(mx_client_from_config(cfg, path = path, app = app))
}
