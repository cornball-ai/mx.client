% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_room_key_payload}
\alias{mx_crypto_room_key_payload}
\title{Encrypt a Megolm room key to one device as a to-device payload}
\usage{
mx_crypto_room_key_payload(olm_session, sender_curve25519,
                           recipient_curve25519, room_id, megolm_out)
}
\arguments{
\item{olm_session}{An outbound Olm session
(\code{mx.crypto::mxc_olm_create_outbound()}).}

\item{sender_curve25519}{Character. This device's Curve25519 key.}

\item{recipient_curve25519}{Character. Target device's Curve25519 key.}

\item{room_id}{Character. Room the key is for.}

\item{megolm_out}{An outbound Megolm session.}
}
\value{
A named list: the to-device \code{m.room.encrypted} content.
}
\description{
Wraps the outbound Megolm session's key in an \code{m.room_key} event,
Olm-encrypts it to the recipient device, and returns the
\code{m.room.encrypted} to-device content to hand to
\code{mx.api::mx_send_to_device()}.
}
\examples{
\dontrun{
content <- mx_crypto_room_key_payload(olm, my_curve, their_curve,
                                      "!room:ex", megolm_out)
}
}
