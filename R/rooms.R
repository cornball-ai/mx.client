# Room lookup and resolution.

#' Look up a joined room by display name
#'
#' @param client Matrix client config.
#' @param name Character room name.
#' @return Room id, or NULL when no joined room has that name.
#' @export
mx_room_lookup_by_name <- function(client, name) {
    if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
        stop("name must be a non-empty character scalar", call. = FALSE)
    }
    s <- mx_client_session(client)
    rooms <- tryCatch(mx.api::mx_rooms(s), error = function(e) character())
    for (rid in rooms) {
        nm <- tryCatch(mx.api::mx_room_name(s, rid), error = function(e) NULL)
        if (!is.null(nm) && identical(nm, name)) {
            return(rid)
        }
    }
    NULL
}

#' Resolve a room id, name, or default room
#'
#' Resolution order:
#' literal room IDs beginning with \code{!}, a supplied \code{room_cache}
#' name-to-id map, joined-room display-name lookup, then the config's
#' \code{room_id} fallback.
#'
#' @param client Matrix client config.
#' @param room Character or NULL.
#' @param room_cache Named list or character vector mapping names to ids.
#' @param fallback Logical. Use \code{client$room_id} when lookup misses.
#' @param details Logical. Return source metadata instead of just the id.
#' @param quiet Logical. Suppress fallback message.
#' @return Character room id, or a list when \code{details = TRUE}.
#' @export
mx_resolve_room <- function(client, room = NULL, room_cache = NULL,
                            fallback = TRUE, details = FALSE, quiet = FALSE) {
    done <- function(room_id, source) {
        if (isTRUE(details)) {
            list(room_id = room_id, source = source)
        } else {
            room_id
        }
    }

    default_room <- client$room_id
    if (is.null(room) || !nzchar(room)) {
        if (is.null(default_room) || !nzchar(default_room)) {
            stop("room is NULL and client has no default room_id",
                 call. = FALSE)
        }
        return(done(default_room, "default"))
    }
    if (!is.character(room) || length(room) != 1L) {
        stop("room must be NULL or a character scalar", call. = FALSE)
    }
    if (startsWith(room, "!")) {
        return(done(room, "literal"))
    }

    cached <- room_cache[[room]]
    if (!is.null(cached) && length(cached) == 1L && nzchar(cached)) {
        return(done(unname(cached), "cache"))
    }

    rid <- mx_room_lookup_by_name(client, room)
    if (!is.null(rid)) {
        return(done(rid, "lookup"))
    }

    if (!isTRUE(fallback)) {
        stop(sprintf("No joined room named %s", sQuote(room)), call. = FALSE)
    }
    if (is.null(default_room) || !nzchar(default_room)) {
        stop(sprintf("No joined room named %s and no default room_id is set",
                     sQuote(room)), call. = FALSE)
    }
    if (!isTRUE(quiet)) {
        message(sprintf("mx.client: no joined room named %s; using default",
                        room))
    }
    done(default_room, "fallback")
}


#' Is a room end-to-end encrypted?
#'
#' Resolves the room (by name, id, or the config default) and reads its
#' \code{m.room.encryption} state. Needs mx.api >= 0.3.0.
#'
#' @param client Matrix client config.
#' @param room Character room id/name or NULL for the default room.
#' @param room_cache Optional room name-to-id cache.
#' @return TRUE when the room advertises an encryption algorithm,
#'   FALSE otherwise.
#' @examples
#' \dontrun{
#' if (mx_room_encrypted(client, "secret plans")) {
#'     # use mx_send_encrypted() instead of mx_send_text()
#' }
#' }
#' @export
mx_room_encrypted <- function(client, room = NULL, room_cache = NULL) {
    rid <- mx_resolve_room(client, room, room_cache = room_cache)
    enc <- mx.api::mx_get_state(mx_client_session(client), rid,
                                "m.room.encryption")
    !is.null(enc$algorithm)
}
