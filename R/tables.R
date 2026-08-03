# Matrix HTML table helpers.

mx_table_coerce <- function(x) {
    if (is.data.frame(x)) {
        return(x)
    }
    if (is.matrix(x)) {
        return(as.data.frame(x, stringsAsFactors = FALSE))
    }
    if (is.list(x)) {
        return(as.data.frame(x, stringsAsFactors = FALSE, check.names = FALSE))
    }
    stop("x must be a data.frame, matrix, or list", call. = FALSE)
}

mx_table_plain <- function(x, header = TRUE) {
    x <- mx_table_coerce(x)
    rows <- vapply(seq_len(nrow(x)), function(i) {
        paste(vapply(x[i,, drop = FALSE], as.character, character(1)),
              collapse = " | ")
    }, character(1))
    # Track the HTML: emitting column names in the fallback while the
    # formatted_body omits them shows different tables to different clients.
    if (isTRUE(header)) {
        rows <- c(paste(names(x), collapse = " | "), rows)
    }
    paste(rows, collapse = "\n")
}

#' Render tabular data as Matrix custom HTML
#'
#' Produces the conservative table shape rendered by Matrix clients such as
#' FluffyChat 2.6.0+: a bare \code{<table>} containing \code{<tr>},
#' \code{<th>}, and \code{<td>} nodes. No CSS, colspan, rowspan, or custom
#' attributes are emitted.
#'
#' @param x A data frame, matrix, or list coercible to a data frame.
#' @param header Logical. Include a header row using column names.
#' @return Character HTML suitable for Matrix \code{formatted_body}.
#' @examples
#' mx_table_html(data.frame(A = 1:2, B = c("x", "y")))
#' @export
mx_table_html <- function(x, header = TRUE) {
    x <- mx_table_coerce(x)
    cell <- function(tag, value) {
        sprintf("<%s>%s</%s>", tag, mx_html_escape(as.character(value)), tag)
    }
    rows <- character()
    if (isTRUE(header)) {
        rows <- c(rows, paste0("<tr>",
                               paste(vapply(names(x), cell, character(1), tag = "th"),
                                     collapse = ""),
                               "</tr>"))
    }
    if (nrow(x)) {
        rows <- c(rows, vapply(seq_len(nrow(x)), function(i) {
            vals <- vapply(x[i,, drop = FALSE], as.character, character(1))
            paste0("<tr>", paste(vapply(vals, cell, character(1), tag = "td"),
                                 collapse = ""), "</tr>")
        }, character(1)))
    }
    paste0("<table>", paste(rows, collapse = ""), "</table>")
}

#' Send tabular data to a Matrix room
#'
#' Sends a plain-text fallback body plus Matrix custom HTML table in
#' \code{formatted_body}. This bypasses Markdown entirely.
#'
#' @param client Matrix client config.
#' @param x A data frame, matrix, or list coercible to a data frame.
#' @param room Character room id/name or NULL for the default room.
#' @param header Logical. Include a header row using column names.
#' @param title Optional text prepended to the plain fallback body.
#' @param room_cache Optional room name-to-id cache.
#' @param dry_run Logical. Print instead of sending.
#' @return Event id, or NULL on dry-run.
#' @examples
#' client <- list(room_id = "!default:example.org")
#' mx_send_table(client, data.frame(A = 1, B = 2), dry_run = TRUE)
#' @export
mx_send_table <- function(client, x, room = NULL, header = TRUE,
                          title = NULL, room_cache = NULL, dry_run = FALSE) {
    html <- mx_table_html(x, header = header)
    body <- mx_table_plain(x, header = header)
    if (!is.null(title) && nzchar(title)) {
        body <- paste(as.character(title), body, sep = "\n")
    }
    if (isTRUE(dry_run)) {
        message("=== mx_send_table (dry-run) [", room %||% "default",
                "] ===\n", body, "\n--- formatted_body ---\n", html)
        return(invisible(NULL))
    }
    rid <- mx_resolve_room(client, room, room_cache = room_cache)
    mx.api::mx_send(mx_client_session(client), rid, body, msgtype = "m.text",
                    extra = list(format = "org.matrix.custom.html", formatted_body = html))
}
