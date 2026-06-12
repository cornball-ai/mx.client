% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_send_media}
\alias{mx_send_media}
\title{Send a media file to a Matrix room}
\usage{
mx_send_media(client, path, room = NULL, body = basename(path), msgtype = NULL,
              content_type = NULL, info = list(), room_cache = NULL,
              dry_run = FALSE)
}
\arguments{
\item{client}{Matrix client config.}

\item{path}{Character. Path to the file to upload.}

\item{room}{Character room id/name or NULL for the default room.}

\item{body}{Character. Message body / filename shown by clients.}

\item{msgtype}{Character or NULL. NULL derives it from the MIME type.}

\item{content_type}{Character or NULL. MIME type override for files
whose extension guesses wrong (tempfiles, odd extensions); NULL
guesses from the extension.}

\item{info}{List. Extra fields merged into the media \code{info}.}

\item{room_cache}{Optional room name-to-id cache.}

\item{dry_run}{Logical. Print instead of uploading/sending.}
}
\value{
Event id, or NULL on dry-run.
}
\description{
Client-layer wrapper over \code{mx.api::mx_send_media()}: resolves the
room by name (or falls back to the config's default room), builds the
session from the client config, and uploads + posts in one call. The
msgtype is derived from the file's MIME type unless given.
}
\details{
If you attach mx.api and mx.client together, namespace-qualify -- the
two packages export an \code{mx_send_media} each (session-first there,
client-first here).

}
\examples{
client <- list(room_id = "!default:example.org")
png <- file.path(tempdir(), "plot.png")
file.create(png)
mx_send_media(client, png, dry_run = TRUE)
unlink(png)
}
