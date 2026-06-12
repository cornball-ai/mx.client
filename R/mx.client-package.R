# Package-level documentation.

#' mx.client: Stateful Matrix Client Helpers
#'
#' Stateful helpers for building 'Matrix' chat clients in R, layered on
#' the low-level \pkg{mx.api} Client-Server API bindings: local
#' configuration persistence, room resolution, sync cursor handling,
#' sync-event extraction, invite acceptance, a conservative
#' Markdown-to-HTML converter, and Olm/Megolm end-to-end encryption
#' orchestration over the optional \pkg{mx.crypto} package.
#'
#' @seealso \code{\link{mx_client_configure}} to create a config,
#'   \code{\link{mx_client_load}} / \code{\link{mx_client_session}} to use
#'   one, \code{\link{mx_send_text}} and \code{\link{mx_sync_update}} for
#'   the core send/receive loop.
#' @name mx.client-package
#' @aliases mx.client
"_PACKAGE"
