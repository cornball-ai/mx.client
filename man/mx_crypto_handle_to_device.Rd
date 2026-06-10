% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_handle_to_device}
\alias{mx_crypto_handle_to_device}
\title{Decrypt an inbound Olm to-device payload}
\usage{
mx_crypto_handle_to_device(account, my_curve25519, content)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{my_curve25519}{Character. This device's Curve25519 key.}

\item{content}{The to-device \code{m.room.encrypted} content.}
}
\value{
The decrypted event (a parsed list), or NULL if not for us.
}
\description{
Accepts an \code{m.room.encrypted} to-device content addressed to this
device and returns the decrypted event. When it is an \code{m.room_key},
the caller builds an inbound Megolm session from
\code{content$session_key} with \code{mx_crypto_inbound_session()}.
}
\examples{
\dontrun{
ev <- mx_crypto_handle_to_device(acct, my_curve, td_content)
if (identical(ev$type, "m.room_key")) {
  inb <- mx_crypto_inbound_session(ev$content$session_key)
}
}
}
