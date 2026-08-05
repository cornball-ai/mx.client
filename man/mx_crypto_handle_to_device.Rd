% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_handle_to_device}
\alias{mx_crypto_handle_to_device}
\title{Decrypt an inbound Olm to-device payload}
\usage{
mx_crypto_handle_to_device(
  account,
  my_curve25519,
  content,
  self_id = NULL,
  self_ed25519 = NULL,
  devices = NULL
)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{my_curve25519}{Character. This device's Curve25519 key.}

\item{content}{The to-device \code{m.room.encrypted} content.}

\item{self_id}{Character or NULL. This user's Matrix id. When NULL the
recipient user-id check is skipped; pass it whenever it is known.}

\item{self_ed25519}{Character or NULL. This device's Ed25519 key.
Defaults to the account's own key.}

\item{devices}{List of verified devices from
\code{mx_crypto_known_devices()}, or NULL. Used to tie the payload's
claimed sender to a device whose keys were verified. The result
carries \code{sender_bound}, which is FALSE when no list is supplied
or nothing matches; an unbound sender identity is a claim, not a
fact, because anyone can open an Olm session to this device.}
}
\value{
The decrypted event (a parsed list) with a \code{sender_bound}
  flag, or NULL if it was not for us or failed the recipient checks.
}
\description{
Accepts an \code{m.room.encrypted} to-device content addressed to this
device and returns the decrypted event. When it is an \code{m.room_key},
the caller builds an inbound Megolm session from
\code{content$session_key} with \code{mx_crypto_inbound_session()}.
}
\details{
The decrypted payload is checked against this device's identity before
it is returned: a message that does not name us as recipient is
dropped, because decrypting successfully only proves it was encrypted
to our key, not that it was meant for us here.

}
\examples{
\dontrun{
ev <- mx_crypto_handle_to_device(acct, my_curve, td_content,
                                 self_id = "@me:example.org",
                                 devices = mx_crypto_known_devices(cl, uid))
if (identical(ev$type, "m.room_key") && isTRUE(ev$sender_bound)) {
  inb <- mx_crypto_inbound_session(ev$content$session_key)
}
}
}
