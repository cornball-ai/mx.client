% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_send_text}
\alias{mx_send_text}
\title{Send plain text to a Matrix room}
\usage{
mx_send_text(client, text, room = NULL, msgtype = "m.text", room_cache = NULL,
             dry_run = FALSE)
}
\arguments{
\item{client}{Matrix client config.}

\item{text}{Character message body.}

\item{room}{Character room id/name or NULL for the default room.}

\item{msgtype}{Character Matrix message type.}

\item{room_cache}{Optional room name-to-id cache.}

\item{dry_run}{Logical. Print instead of sending.}
}
\value{
Event id, or NULL on dry-run.
}
\description{
Send plain text to a Matrix room
}
