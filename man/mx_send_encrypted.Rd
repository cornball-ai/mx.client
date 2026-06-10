% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_send_encrypted}
\alias{mx_send_encrypted}
\title{Send an end-to-end encrypted message to a room}
\usage{
mx_send_encrypted(client, account, sessions, room_id, content, store_dir,
                  recipients = NULL, member_ids = NULL)
}
\arguments{
\item{client}{Matrix client config.}

\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set (see \code{mx_crypto_sessions_new()}).}

\item{room_id}{Character room id.}

\item{content}{Named list. Plaintext event content.}

\item{store_dir}{Character. Crypto store directory.}

\item{recipients}{List of recipient devices, or NULL to discover them
from \code{member_ids}.}

\item{member_ids}{Character vector of room member user ids (used when
\code{recipients} is NULL).}
}
\value{
List with \code{event_id} and the updated \code{sessions}.
}
\description{
Discovers the room members' devices (unless \code{recipients} is given),
claims one-time keys for any without an Olm session, shares the room key
over to-device, encrypts the content with Megolm, sends the
\code{m.room.encrypted} event, and persists the updated sessions.
}
\examples{
\dontrun{
res <- mx_send_encrypted(client, acct, sessions, "!r:ex",
  list(msgtype = "m.text", body = "secret"), store,
  member_ids = "@bob:example.org")
}
}
