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
#' @param mentions Character vector of Matrix user ids to mention
#'   (e.g. \code{"@jorge:cornball.ai"}). Each id is added to the event's
#'   \code{m.mentions} (so the user is notified) and any textual
#'   \code{@localpart} in the body becomes a \code{matrix.to} pill in the
#'   HTML. Implies an HTML formatted body even when \code{markdown} is
#'   FALSE -- pills only render from HTML.
#' @param thread Event id of a thread root, or NULL for an ordinary
#'   message. The event is sent as a threaded reply
#'   (\code{m.relates_to} with \code{rel_type} \code{"m.thread"}).
#'
#'   It also carries the reply fallback the spec asks for --
#'   \code{is_falling_back} with an \code{m.in_reply_to} pointing at the
#'   root -- so a client that does not implement threads renders the
#'   message as a reply to the root rather than as a loose message in
#'   the room. Without it those clients show a threaded conversation
#'   as unattached chatter.
#' @return Event id, or NULL on dry-run.
#' @examples
#' client <- list(room_id = "!default:example.org")
#' mx_send_text(client, "release is out", dry_run = TRUE)
#' \dontrun{
#' # A real send needs a live homeserver session:
#' client <- mx_client_load("myapp")
#' mx_send_text(client, "release is out", markdown = TRUE,
#'              mentions = "@jorge:example.org")
#' }
#' @export
mx_send_text <- function(client, text, room = NULL, msgtype = "m.text",
                         room_cache = NULL, dry_run = FALSE,
                         markdown = FALSE, mentions = NULL, thread = NULL) {
    rid <- mx_resolve_room(client, room, room_cache = room_cache)
    if (isTRUE(dry_run)) {
        message("=== mx_send_text (dry-run) [", room %||% "default",
                "] ===\n", text)
        return(invisible(NULL))
    }
    extra <- NULL
    if (isTRUE(markdown) || length(mentions)) {
        html <- mx_markdown_to_html(text)
        if (length(mentions)) {
            html <- mx_pill_mentions(html, mentions)
        }
        extra <- list(format = "org.matrix.custom.html", formatted_body = html)
    }
    if (length(mentions)) {
        extra <- c(extra,
                   list("m.mentions" = list(user_ids = as.list(mentions))))
    }
    if (!is.null(thread) && length(thread) && nzchar(thread[[1L]])) {
        extra <- c(extra, list("m.relates_to" = list(
                    rel_type = "m.thread",
                    event_id = as.character(thread)[[1L]],
                    # The reply fallback: thread-unaware clients read
                    # m.in_reply_to and render this as a reply to the root.
                    is_falling_back = TRUE,
                    "m.in_reply_to" = list(
                        event_id = as.character(thread)[[1L]]))))
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
#' @examples
#' \dontrun{
#' # Needs a live homeserver session.
#' client <- mx_client_load("myapp")
#' res <- mx_sync_update(client, timeout = 30000L)
#' events <- mx_extract_text_events(res$sync, client$user_id)
#' }
#' @export
mx_sync_update <- function(client, timeout = 0L, filter = NULL, save = TRUE,
                           path = NULL, app = NULL) {
    first_run <- is.null(client$sync_token)
    sync <- mx.api::mx_sync(mx_client_session(client),
                            since = client$sync_token,
                            timeout = as.integer(timeout), filter = filter)
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
#' @return List of normalized event records, each carrying
#'   \code{room_id}, \code{event_id}, \code{sender}, \code{is_self},
#'   \code{body}, \code{msgtype}, \code{ts} (the event's
#'   \code{origin_server_ts}, in milliseconds since the epoch, or NULL
#'   when the server omits it), \code{mentions}, and \code{relates_to}.
#'
#'   \code{relates_to} is the event's \code{m.relates_to} content,
#'   verbatim, or NULL. It is what distinguishes a threaded reply
#'   (\code{rel_type} of \code{m.thread}) from a rich reply (an
#'   \code{m.in_reply_to} with no \code{rel_type}) from an edit
#'   (\code{m.replace}), and dropping it left every caller unable to tell
#'   any of them from an ordinary message. Passed through rather than
#'   interpreted: which of those a caller cares about is its own business.
#' @examples
#' sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
#'     timeline = list(events = list(list(type = "m.room.message",
#'         event_id = "$1", sender = "@alice:example.org",
#'         content = list(msgtype = "m.text", body = "hello"))))))))
#' mx_extract_text_events(sync_resp, self_id = "@bot:example.org")
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
                out[[length(out) + 1L]] <- list(room_id = rid,
                    event_id = ev$event_id, sender = ev$sender,
                    is_self = isTRUE(ev$sender == self_id),
                    body = ev$content$body, msgtype = ev$content$msgtype,
                    ts = ev$origin_server_ts,
                    mentions = ev$content$`m.mentions`$user_ids,
                    relates_to = ev$content$`m.relates_to`)
            }
        }
    }
    out
}

#' Extract media message events from a sync response
#'
#' Walks joined-room timeline events and returns normalized media
#' records: images, files, audio, and video sent as
#' \code{m.room.message} events. Self events are retained and tagged
#' with \code{is_self}, as in \code{\link{mx_extract_text_events}}.
#'
#' Cleartext media carries its content address in \code{content$url};
#' end-to-end encrypted media carries a \code{content$file} object
#' (address, key material, sha256) instead. \code{url} is filled from
#' whichever is present, so a consumer that only wants to know where
#' the bytes live reads one field. \code{file} rides verbatim, the
#' \code{relates_to} treatment: decrypting is the caller's business,
#' and an extractor inventing a partial view of key material would
#' help no one.
#'
#' \code{m.sticker} is its own event type, not an
#' \code{m.room.message} msgtype, and is not reported here.
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @param self_id Current user's Matrix id.
#' @param msgtypes Character vector of media message types to include.
#' @return List of normalized records, each carrying \code{room_id},
#'   \code{event_id}, \code{sender}, \code{is_self}, \code{body} (the
#'   filename, or the caption when \code{filename} is set),
#'   \code{filename} (or NULL), \code{msgtype}, \code{ts} (or NULL),
#'   \code{url} (the mxc address, from \code{content$url} or
#'   \code{content$file$url}), \code{mime} (or NULL), \code{size} (or
#'   NULL), \code{sha256} (from the encrypted file object; cleartext
#'   media carries no hash, so NULL there), \code{encrypted},
#'   \code{file} (the \code{content$file} object verbatim, or NULL),
#'   \code{mentions}, and \code{relates_to}.
#'
#'   An event with no address in either place is skipped: there is
#'   nothing a consumer could ever fetch, so reporting it would hand
#'   out a record whose one job is impossible.
#' @examples
#' sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
#'     timeline = list(events = list(list(type = "m.room.message",
#'         event_id = "$1", sender = "@alice:example.org",
#'         content = list(msgtype = "m.image", body = "plot.png",
#'             url = "mxc://example.org/abc",
#'             info = list(mimetype = "image/png", size = 1024)))))))))
#' mx_extract_media_events(sync_resp, self_id = "@bot:example.org")
#' @export
mx_extract_media_events <- function(sync_resp, self_id,
                                    msgtypes = c("m.image", "m.file", "m.audio", "m.video")) {
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
            # Every content read below is [[ ]], not $, and that is the
            # whole of this function's history. `$` on a list partial-
            # matches: an image whose content carries `filename` -- which
            # is what a client sends when the body is a caption, and what
            # Element sends for an ordinary photo -- makes
            # `content$file` resolve to that filename string. Then
            # `content$file$hashes` is `$` on a character vector, which
            # is an error, and `encrypted` is TRUE for a cleartext
            # picture. The first live image this saw threw exactly that.
            #
            # The fixtures did not catch it because none of them carried
            # a `filename`, which is the field that creates the
            # ambiguity. There is one below now.
            content <- ev[["content"]]
            if (!is.list(content) ||
                !isTRUE(ev[["type"]] == "m.room.message") ||
                !isTRUE(content[["msgtype"]] %in% msgtypes)) {
                next
            }
            file <- content[["file"]]
            url <- content[["url"]] %||%
            if (is.list(file)) {
                file[["url"]]
            } else {
                NULL
            }
            if (is.null(url)) {
                next
            }
            info <- content[["info"]]
            if (!is.list(info)) {
                info <- list()
            }
            if (is.list(file)) {
                hashes <- file[["hashes"]]
            } else {
                hashes <- NULL
            }
            mentions <- content[["m.mentions"]]
            out[[length(out) + 1L]] <- list(room_id = rid,
                event_id = ev[["event_id"]], sender = ev[["sender"]],
                is_self = isTRUE(ev[["sender"]] == self_id),
                body = content[["body"]],
                filename = content[["filename"]],
                msgtype = content[["msgtype"]],
                ts = ev[["origin_server_ts"]],
                url = url,
                mime = info[["mimetype"]],
                size = info[["size"]],
                sha256 = if (is.list(hashes)) hashes[["sha256"]] else NULL,
                # is.list, not !is.null: the `file` object is what makes
                # a media event encrypted, and a stray string in that
                # slot is not one.
                encrypted = is.list(file),
                file = if (is.list(file)) file else NULL,
                mentions = if (is.list(mentions)) {
                    mentions[["user_ids"]]
                } else {
                    NULL
                },
                relates_to = content[["m.relates_to"]])
        }
    }
    out
}

#' Extract pending invite room ids from a sync response
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @return Character vector of invited room ids.
#' @examples
#' sync_resp <- list(rooms = list(invite = list("!inv:example.org" = list())))
#' mx_extract_invites(sync_resp)
#' @export
mx_extract_invites <- function(sync_resp) {
    invited <- sync_resp$rooms$invite
    if (!length(invited)) {
        return(character())
    }
    names(invited)
}

#' Extract pending invites with the member who sent them
#'
#' The fuller form of \code{\link{mx_extract_invites}}, which reports
#' only room ids. An invite's sender is the whole of whether it should be
#' accepted -- auto-joining anyone's invite hands a stranger a session
#' with whatever the client can do -- and a caller that wants to decide
#' had to walk \code{invite_state} itself to find out.
#'
#' The sender comes from the stripped state the homeserver sends
#' alongside an invite: the \code{m.room.member} event whose
#' \code{state_key} is \code{self_id} and whose membership is
#' \code{"invite"}. That is not always present, so \code{inviter} is NA
#' when it is missing rather than guessed at, and a caller gating on it
#' can tell "nobody I trust" from "I could not tell".
#'
#' Stripped state carries no reliable \code{origin_server_ts}, so there
#' is no timestamp here. An invite is a standing state, not an event at a
#' moment.
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @param self_id Current user's Matrix id, whose membership event names
#'   the inviter. NULL reports every invite with \code{inviter} NA.
#' @return List of records, each \code{list(room_id, inviter)}.
#' @examples
#' sync_resp <- list(rooms = list(invite = list(`!inv:example.org` = list(
#'     invite_state = list(events = list(list(type = "m.room.member",
#'         state_key = "@bot:example.org", sender = "@ann:example.org",
#'         content = list(membership = "invite"))))))))
#' mx_extract_invite_records(sync_resp, self_id = "@bot:example.org")
#' @export
mx_extract_invite_records <- function(sync_resp, self_id = NULL) {
    invited <- sync_resp$rooms$invite
    if (!length(invited)) {
        return(list())
    }
    lapply(names(invited), function(rid) {
        who <- NA_character_
        if (!is.null(self_id)) {
            for (ev in invited[[rid]]$invite_state$events %||% list()) {
                if (isTRUE(ev$type == "m.room.member") &&
                    isTRUE(ev$state_key == self_id) &&
                    isTRUE(ev$content$membership == "invite")) {
                    who <- ev$sender %||% NA_character_
                    break
                }
            }
        }
        list(room_id = rid, inviter = who)
    })
}

#' Accept pending Matrix room invites
#'
#' @param client Matrix client config.
#' @param invites Character vector of room ids.
#' @return Character vector of joined room ids.
#' @examples
#' \dontrun{
#' # Needs a live homeserver session.
#' client <- mx_client_load("myapp")
#' res <- mx_sync_update(client)
#' mx_accept_invites(res$client, mx_extract_invites(res$sync))
#' }
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
            message(sprintf("mx.client: failed to join %s: %s", rid,
                            conditionMessage(e)))
            NULL
        }
        )
        if (!is.null(out)) {
            joined <- c(joined, out)
        }
    }
    joined
}

#' Extract reaction events from a sync response
#'
#' Walks joined-room timelines and returns every \code{m.reaction} that
#' annotates another event. Self reactions are retained and tagged with
#' \code{is_self}, the same way \code{\link{mx_extract_text_events}}
#' treats the client's own messages: a consumer that wants only other
#' people's reactions filters on the flag, and one tracking its own
#' (which reactions it has already placed) needs them.
#'
#' This is the general form of \code{\link{mx_extract_reaction_verdict}},
#' which answers one approve/deny question about one event. That function
#' bakes in which keys mean yes and which mean no, and stays for callers
#' who want that; this one reports keys and leaves their meaning alone.
#'
#' Only additions are reported. Removing a reaction is an
#' \code{m.room.redaction} of the \code{m.reaction} event, which is not an
#' \code{m.reaction} and so does not appear here -- a consumer that has to
#' notice un-reactions needs to read redactions itself.
#'
#' @param sync_resp Parsed \code{/sync} response.
#' @param self_id Current user's Matrix id.
#' @return List of records, each carrying \code{room_id},
#'   \code{event_id} (the reaction's own id, not its target),
#'   \code{sender}, \code{is_self}, \code{target_event_id} (the annotated
#'   event), \code{key} (the reaction text, usually an emoji), and
#'   \code{ts} (\code{origin_server_ts} in milliseconds, or NULL when the
#'   server omits it). An \code{m.reaction} carrying no annotation
#'   relation, no target, or no key is not a reaction to anything and is
#'   skipped.
#' @examples
#' sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
#'     timeline = list(events = list(list(type = "m.reaction",
#'         event_id = "$r1", sender = "@alice:example.org",
#'         content = list("m.relates_to" = list(rel_type = "m.annotation",
#'             event_id = "$msg", key = "+1")))))))))
#' mx_extract_reactions(sync_resp, self_id = "@bot:example.org")
#' @export
mx_extract_reactions <- function(sync_resp, self_id) {
    joined <- sync_resp$rooms$join
    if (!length(joined)) {
        return(list())
    }
    out <- list()
    for (rid in names(joined)) {
        for (ev in joined[[rid]]$timeline$events %||% list()) {
            if (!isTRUE(ev$type == "m.reaction")) {
                next
            }
            rel <- ev$content$`m.relates_to`
            # rel_type is checked rather than assumed: m.reaction is
            # defined to carry m.annotation, and an event using it for
            # something else is not a reaction whose target we can name.
            if (!is.list(rel) || !isTRUE(rel$rel_type == "m.annotation")) {
                next
            }
            if (!is.character(rel$event_id) || !length(rel$event_id) ||
                !is.character(rel$key) || !length(rel$key)) {
                next
            }
            out[[length(out) + 1L]] <- list(room_id = rid,
                event_id = ev$event_id, sender = ev$sender,
                is_self = isTRUE(ev$sender == self_id),
                target_event_id = rel$event_id, key = rel$key,
                ts = ev$origin_server_ts)
        }
    }
    out
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
#' @param approve_keys Character vector of reaction keys read as approval.
#'   \code{NULL} (default) uses thumbs-up (U+1F44D), check-mark (U+2705),
#'   and \code{"y"}/\code{"yes"}/\code{"ok"}.
#' @param deny_keys Character vector of reaction keys read as denial.
#'   \code{NULL} (default) uses thumbs-down (U+1F44E), cross-mark
#'   (U+274C), and \code{"n"}/\code{"no"}/\code{"nope"}.
#' @return TRUE, FALSE, or NULL.
#' @examples
#' sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
#'     timeline = list(events = list(list(type = "m.reaction",
#'         sender = "@alice:example.org",
#'         content = list("m.relates_to" = list(rel_type = "m.annotation",
#'             event_id = "$msg", key = "yes")))))))))
#' mx_extract_reaction_verdict(sync_resp, "!room:example.org",
#'                             self_id = "@bot:example.org",
#'                             target_event_id = "$msg")
#' @export
mx_extract_reaction_verdict <- function(sync_resp, room_id, self_id,
                                        target_event_id, approve_keys = NULL,
                                        deny_keys = NULL) {
    # Emoji defaults are built here, not in the signature, so they don't
    # land as raw astral-plane glyphs in the .Rd \usage block -- LaTeX
    # can't typeset them and the PDF manual fails R CMD check --as-cran.
    if (is.null(approve_keys)) {
        approve_keys <- c(intToUtf8(0x1F44D), intToUtf8(0x2705), "y", "yes",
                          "ok")
    }
    if (is.null(deny_keys)) {
        deny_keys <- c(intToUtf8(0x1F44E), intToUtf8(0x274C), "n", "no", "nope")
    }
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
#' @examples
#' client <- list(room_id = "!default:example.org")
#' png <- file.path(tempdir(), "plot.png")
#' file.create(png)
#' mx_send_media(client, png, dry_run = TRUE)
#' unlink(png)
#' @export
mx_send_media <- function(client, path, room = NULL, body = basename(path),
                          msgtype = NULL, content_type = NULL, info = list(),
                          room_cache = NULL, dry_run = FALSE) {
    rid <- mx_resolve_room(client, room, room_cache = room_cache)
    if (isTRUE(dry_run)) {
        message("=== mx_send_media (dry-run) [", room %||% "default",
                "] ===\n", path, " (",
                content_type %||% mx.api::mx_guess_mime(path), ")")
        return(invisible(NULL))
    }
    mx.api::mx_send_media(mx_client_session(client), rid, path,
                          body = body, msgtype = msgtype,
                          content_type = content_type, info = info)
}
