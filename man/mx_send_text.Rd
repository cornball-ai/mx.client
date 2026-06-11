% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_send_text}
\alias{mx_send_text}
\title{Send plain text to a Matrix room}
\usage{
mx_send_text(client, text, room = NULL, msgtype = "m.text", room_cache = NULL,
             dry_run = FALSE, markdown = FALSE, mentions = NULL)
}
\arguments{
\item{client}{Matrix client config.}

\item{text}{Character message body.}

\item{room}{Character room id/name or NULL for the default room.}

\item{msgtype}{Character Matrix message type.}

\item{room_cache}{Optional room name-to-id cache.}

\item{dry_run}{Logical. Print instead of sending.}

\item{markdown}{Logical. If TRUE, include Matrix custom HTML derived
from a conservative markdown subset.}

\item{mentions}{Character vector of Matrix user ids to mention
(e.g. \code{"@jorge:cornball.ai"}). Each id is added to the event's
\code{m.mentions} (so the user is notified) and any textual
\code{@localpart} in the body becomes a \code{matrix.to} pill in the
HTML. Implies an HTML formatted body even when \code{markdown} is
FALSE -- pills only render from HTML.}
}
\value{
Event id, or NULL on dry-run.
}
\description{
Send plain text to a Matrix room
}
