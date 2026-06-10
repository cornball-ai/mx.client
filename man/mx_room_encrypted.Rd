% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_room_encrypted}
\alias{mx_room_encrypted}
\title{Is a room end-to-end encrypted?}
\usage{
mx_room_encrypted(client, room = NULL, room_cache = NULL)
}
\arguments{
\item{client}{Matrix client config.}

\item{room}{Character room id/name or NULL for the default room.}

\item{room_cache}{Optional room name-to-id cache.}
}
\value{
TRUE when the room advertises an encryption algorithm,
  FALSE otherwise.
}
\description{
Resolves the room (by name, id, or the config default) and reads its
\code{m.room.encryption} state. Needs mx.api >= 0.3.0.
}
\examples{
\dontrun{
if (mx_room_encrypted(client, "secret plans")) {
    # use mx_send_encrypted() instead of mx_send_text()
}
}
}
