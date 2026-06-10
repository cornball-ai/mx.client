% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_encrypt_for_devices}
\alias{mx_crypto_encrypt_for_devices}
\title{Encrypt an event for an encrypted room's devices}
\usage{
mx_crypto_encrypt_for_devices(account, sessions, room_id, content,
                              sender_curve25519, device_id, recipients = list())
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set.}

\item{room_id}{Character room id.}

\item{content}{Named list. Plaintext event content.}

\item{sender_curve25519}{Character. This device's Curve25519 key.}

\item{device_id}{Character. This device's id.}

\item{recipients}{List of recipient devices, each a list with
\code{user_id}, \code{device_id}, \code{curve25519}, and (only needed
to open a new Olm session) \code{otk}, a claimed one-time key.}
}
\value{
List with \code{to_device} (per-device payloads), \code{event}
  (the \code{m.room.encrypted} content), and the updated \code{sessions}.
}
\description{
Ensures an outbound Megolm session for the room, shares its key with
any recipient device that has not received it yet (establishing an Olm
session, claiming a one-time key when needed), and encrypts the event.
Returns the to-device payloads and the \code{m.room.encrypted} event;
the caller sends them with \code{mx.api::mx_send_to_device()} and
\code{mx.api::mx_send()}.
}
\examples{
\donttest{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
  acct <- mx.crypto::mxc_account_new()
  out <- mx_crypto_encrypt_for_devices(
    acct, mx_crypto_sessions_new(), "!r:ex",
    list(msgtype = "m.text", body = "hi"),
    mx.crypto::mxc_account_identity_keys(acct)$curve25519, "DEV",
    recipients = list())
  names(out)
}
}
}
