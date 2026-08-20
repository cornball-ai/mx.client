% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_media_events}
\alias{mx_extract_media_events}
\title{Extract media message events from a sync response}
\usage{
mx_extract_media_events(
  sync_resp,
  self_id,
  msgtypes = c("m.image", "m.file", "m.audio", "m.video")
)
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}

\item{self_id}{Current user's Matrix id.}

\item{msgtypes}{Character vector of media message types to include.}
}
\value{
List of normalized records, each carrying \code{room_id},
  \code{event_id}, \code{sender}, \code{is_self}, \code{body} (the
  filename, or the caption when \code{filename} is set),
  \code{filename} (or NULL), \code{msgtype}, \code{ts} (or NULL),
  \code{url} (the mxc address, from \code{content$url} or
  \code{content$file$url}), \code{mime} (or NULL), \code{size} (or
  NULL), \code{sha256} (from the encrypted file object; cleartext
  media carries no hash, so NULL there), \code{encrypted},
  \code{file} (the \code{content$file} object verbatim, or NULL),
  \code{mentions}, and \code{relates_to}.

  An event with no address in either place is skipped: there is
  nothing a consumer could ever fetch, so reporting it would hand
  out a record whose one job is impossible.
}
\description{
Walks joined-room timeline events and returns normalized media
records: images, files, audio, and video sent as
\code{m.room.message} events. Self events are retained and tagged
with \code{is_self}, as in \code{\link{mx_extract_text_events}}.
}
\details{
Cleartext media carries its content address in \code{content$url};
end-to-end encrypted media carries a \code{content$file} object
(address, key material, sha256) instead. \code{url} is filled from
whichever is present, so a consumer that only wants to know where
the bytes live reads one field. \code{file} rides verbatim, the
\code{relates_to} treatment: decrypting is the caller's business,
and an extractor inventing a partial view of key material would
help no one.

\code{m.sticker} is its own event type, not an
\code{m.room.message} msgtype, and is not reported here.

}
\examples{
sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
    timeline = list(events = list(list(type = "m.room.message",
        event_id = "$1", sender = "@alice:example.org",
        content = list(msgtype = "m.image", body = "plot.png",
            url = "mxc://example.org/abc",
            info = list(mimetype = "image/png", size = 1024)))))))))
mx_extract_media_events(sync_resp, self_id = "@bot:example.org")
}
