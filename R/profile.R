# Profile operations: client-level wrappers over mx.api's profile
# endpoints, so callers hand in the client config and get token
# rotation handled instead of building sessions by hand.

#' Set the account's profile display name
#'
#' Client-level wrapper over \code{mx.api::mx_set_displayname()}: builds
#' the session from the client config and retries once through
#' \code{\link{mx_with_relogin}} when the homeserver rejects a rotated
#' token. The display name is account-global and shows in the sender
#' line of every message the account posts.
#'
#' @param client Matrix client config.
#' @param name Character. New display name.
#' @param save Logical. On a relogin, persist the refreshed token to the
#'   client's config path (see \code{\link{mx_client_relogin}}).
#' @return TRUE, invisibly.
#' @examples
#' \dontrun{
#' # A real rename needs a live homeserver session:
#' client <- mx_client_load("myapp")
#' mx_set_displayname(client, "mybot (maintenance)")
#' }
#' @export
mx_set_displayname <- function(client, name, save = TRUE) {
    if (!is.character(name) || length(name) != 1L || is.na(name) ||
            !nzchar(name)) {
        stop("name must be a single non-empty string", call. = FALSE)
    }
    mx_with_relogin(client, function(cl) {
        mx.api::mx_set_displayname(mx_client_session(cl), name)
    }, save = save)
    invisible(TRUE)
}
