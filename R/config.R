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
#' @export
mx_client_from_config <- function(cfg, path = NULL, app = NULL) {
    if (!is.list(cfg)) {
        stop("cfg must be a list", call. = FALSE)
    }
    structure(
              cfg,
              class = unique(c("mx_client_config", class(cfg))),
              path = path,
              app = app
    )
}

mx_client_plain_list <- function(client) {
    out <- unclass(client)
    attr(out, "path") <- NULL
    attr(out, "app") <- NULL
    out
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

