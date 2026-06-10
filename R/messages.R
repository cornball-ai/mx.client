# Message send, sync cursor updates, and sync event extraction.

#' Send plain text to a Matrix room
#'
#' @param client Matrix client config.
#' @param text Character message body.
#' @param room Character room id/name or NULL for the default room.
#' @param msgtype Character Matrix message type.
#' @param room_cache Optional room name-to-id cache.
#' @param dry_run Logical. Print instead of sending.
#' @param markdown Logical. If TRUE, include Matrix custom HTML derived
#'   from a conservative markdown subset.
#' @return Event id, or NULL on dry-run.
#' @export
mx_send_text <- function(client, text, room = NULL, msgtype = "m.text",
                         room_cache = NULL, dry_run = FALSE,
                         markdown = FALSE) {
    rid <- mx_resolve_room(client, room, room_cache = room_cache)
    if (isTRUE(dry_run)) {
        message(
                "=== mx_send_text (dry-run) [", room %||% "default", "] ===\n",
                text
        )
        return(invisible(NULL))
    }
    extra <- NULL
    if (isTRUE(markdown)) {
        extra <- list(format = "org.matrix.custom.html",
                      formatted_body = mx_markdown_to_html(text))
    }
    mx.api::mx_send(mx_client_session(client), rid, text, msgtype = msgtype,
                    extra = extra)
}

#' Sync once and update the stored cursor
#'
#' Calls \code{mx.api::mx_sync()} using \code{client$sync_token}, stores
#' the returned \code{next_batch} in a returned client object, and
#' optionally saves it back to disk.
#'
#' @param client Matrix client config.
#' @param timeout Integer long-poll timeout in milliseconds.
#' @param filter Character or NULL. Matrix sync filter.
#' @param save Logical. Persist the updated client config.
#' @param path Character or NULL. Save destination.
#' @param app Character or NULL. Application namespace for default saves.
#' @return List with \code{sync}, \code{client}, and \code{first_run}.
#' @export
mx_sync_update <- function(client, timeout = 0L, filter = NULL, save = TRUE,
                           path = NULL, app = NULL) {
    first_run <- is.null(client$sync_token)
    sync <- mx.api::mx_sync(
                            mx_client_session(client),
                            since = client$sync_token,
                            timeout = as.integer(timeout),
                            filter = filter
    )
    updated <- mx_client_from_config(
                                     mx_client_plain_list(client),
                                     path = path %||% attr(client, "path"),
                                     app = app %||% attr(client, "app")
    )
    updated$sync_token <- sync$next_batch
    if (isTRUE(save)) {
        updated <- mx_client_save(updated, app = app, path = path)
    }
    list(sync = sync, client = updated, first_run = first_run)
}

#' Extract text message events from a sync response
#'
#' Walks joined-room timeline events and returns normalized text-message
#' records. Self events are retained and tagged with \code{is_self}.
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @param self_id Current user's Matrix id.
#' @param msgtypes Character vector of message types to include.
#' @return List of normalized event records.
#' @export
mx_extract_text_events <- function(sync_resp, self_id, msgtypes = "m.text") {
    joined <- sync_resp$rooms$join
    if (!length(joined)) {
        return(list())
    }

    out <- list()
    for (rid in names(joined)) {
        events <- joined[[rid]]$timeline$events
        if (!length(events)) {
            next
        }
        for (ev in events) {
            if (isTRUE(ev$type == "m.room.message") &&
                isTRUE(ev$content$msgtype %in% msgtypes) &&
                !is.null(ev$content$body)) {
                out[[length(out) + 1L]] <- list(
                    room_id = rid,
                    event_id = ev$event_id,
                    sender = ev$sender,
                    is_self = isTRUE(ev$sender == self_id),
                    body = ev$content$body,
                    msgtype = ev$content$msgtype,
                    mentions = ev$content$`m.mentions`$user_ids
                )
            }
        }
    }
    out
}

#' Extract pending invite room ids from a sync response
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @return Character vector of invited room ids.
#' @export
mx_extract_invites <- function(sync_resp) {
    invited <- sync_resp$rooms$invite
    if (!length(invited)) {
        return(character())
    }
    names(invited)
}

#' Accept pending Matrix room invites
#'
#' @param client Matrix client config.
#' @param invites Character vector of room ids.
#' @return Character vector of joined room ids.
#' @export
mx_accept_invites <- function(client, invites) {
    if (!length(invites)) {
        return(character())
    }
    s <- mx_client_session(client)
    joined <- character()
    for (rid in invites) {
        out <- tryCatch(
                        mx.api::mx_room_join(s, rid),
                        error = function(e) {
            message(sprintf("mx.client: failed to join %s: %s",
                            rid, conditionMessage(e)))
            NULL
        }
        )
        if (!is.null(out)) {
            joined <- c(joined, out)
        }
    }
    joined
}

#' Extract a reaction approval verdict from sync events
#'
#' Scans a room timeline for a reaction on \code{target_event_id} from
#' someone other than \code{self_id}. Returns TRUE for approval keys,
#' FALSE for denial keys, or NULL when no verdict is present.
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @param room_id Character room id.
#' @param self_id Current user's Matrix id.
#' @param target_event_id Event id being reacted to.
#' @param approve_keys Character vector.
#' @param deny_keys Character vector.
#' @return TRUE, FALSE, or NULL.
#' @export
mx_extract_reaction_verdict <- function(sync_resp, room_id, self_id,
                                        target_event_id,
                                        approve_keys = c("\U0001F44D", "\U00002705", "y", "yes", "ok"),
                                        deny_keys = c("\U0001F44E", "\U0000274C", "n", "no", "nope")) {
    room <- sync_resp$rooms$join[[room_id]]
    if (is.null(room)) {
        return(NULL)
    }
    events <- room$timeline$events
    if (!length(events)) {
        return(NULL)
    }

    for (ev in events) {
        if (!isTRUE(ev$type == "m.reaction")) {
            next
        }
        if (isTRUE(ev$sender == self_id)) {
            next
        }
        rel <- ev$content$`m.relates_to`
        if (!is.list(rel) || !identical(rel$event_id, target_event_id)) {
            next
        }
        key <- rel$key
        if (!is.character(key) || !length(key)) {
            next
        }
        if (key %in% approve_keys) {
            return(TRUE)
        }
        if (key %in% deny_keys) {
            return(FALSE)
        }
    }
    NULL
}


#' Send a media file to a Matrix room
#'
#' Client-layer wrapper over \code{mx.api::mx_send_media()}: resolves the
#' room by name (or falls back to the config's default room), builds the
#' session from the client config, and uploads + posts in one call. The
#' msgtype is derived from the file's MIME type unless given.
#'
#' If you attach mx.api and mx.client together, namespace-qualify -- the
#' two packages export an \code{mx_send_media} each (session-first there,
#' client-first here).
#'
#' @param client Matrix client config.
#' @param path Character. Path to the file to upload.
#' @param room Character room id/name or NULL for the default room.
#' @param body Character. Message body / filename shown by clients.
#' @param msgtype Character or NULL. NULL derives it from the MIME type.
#' @param content_type Character or NULL. MIME type override for files
#'   whose extension guesses wrong (tempfiles, odd extensions); NULL
#'   guesses from the extension.
#' @param info List. Extra fields merged into the media \code{info}.
#' @param room_cache Optional room name-to-id cache.
#' @param dry_run Logical. Print instead of uploading/sending.
#' @return Event id, or NULL on dry-run.
#' @export
mx_send_media <- function(client, path, room = NULL, body = basename(path),
                          msgtype = NULL, content_type = NULL, info = list(),
                          room_cache = NULL, dry_run = FALSE) {
    rid <- mx_resolve_room(client, room, room_cache = room_cache)
    if (isTRUE(dry_run)) {
        message(
                "=== mx_send_media (dry-run) [", room %||% "default", "] ===\n",
                path, " (", content_type %||% mx.api::mx_guess_mime(path), ")"
        )
        return(invisible(NULL))
    }
    mx.api::mx_send_media(mx_client_session(client), rid, path,
                          body = body, msgtype = msgtype,
                          content_type = content_type, info = info)
}
