% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_key_parse}
\alias{mx_call_key_parse}
\title{Read a call key event}
\usage{
mx_call_key_parse(event, room_id)
}
\arguments{
\item{event}{List with \code{type}, \code{content} and \code{sender}.}

\item{room_id}{The call's room; keys for other rooms are ignored.}
}
\value{
A list of \code{list(identity, key, index)}, with \code{key} a
  raw vector, one per usable key in the event; empty when the event is
  not a usable key for this room.
}
\description{
Parses a decrypted \code{io.element.call.encryption_keys} to-device
event (from the \code{to_device} list of
\code{\link{mx_crypto_process_sync}}) into the LiveKit identities and
keys to set. The event's \code{keys} field is an array, so one event
can carry several keys at different indices; each becomes one entry.
}
\examples{
ev <- list(type = "io.element.call.encryption_keys",
    sender = "@alice:example.org",
    content = list(
        keys = list(list(index = 3, key = "AAECAwQFBgcICQoLDA0ODw==")),
        member = list(claimed_device_id = "PHONE"), room_id = "!r:example.org"))
mx_call_key_parse(ev, "!r:example.org")
}
