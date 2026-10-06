% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_encrypt_to_device}
\alias{mx_crypto_encrypt_to_device}
\title{Encrypt a to-device event for a set of devices}
\usage{
mx_crypto_encrypt_to_device(
  account,
  sessions,
  event_type,
  content,
  recipients,
  sender_user_id
)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set.}

\item{event_type}{The inner event type, e.g.
\code{"io.element.call.encryption_keys"}.}

\item{content}{Named list. Plaintext event content.}

\item{recipients}{List of recipient devices as returned by
\code{mx_crypto_known_devices()}: \code{user_id}, \code{device_id},
\code{curve25519}, \code{ed25519}, and \code{otk} for a device
without an Olm session yet.}

\item{sender_user_id}{Character. This user's Matrix id.}
}
\value{
List with \code{to_device} (per-device payloads, each
  \code{list(user_id, device_id, content)}) and the updated
  \code{sessions}.
}
\description{
Produces one Olm-encrypted \code{m.room.encrypted} payload per
recipient device, opening an Olm session where none exists yet. Unlike
Megolm room keys, which are shared once per session, the event is
encrypted for every recipient on every call.
}
\examples{
\donttest{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
  acct <- mx.crypto::mxc_account_new()
  out <- mx_crypto_encrypt_to_device(acct, mx_crypto_sessions_new(),
    "org.example.ping", list(n = 1), recipients = list(),
    sender_user_id = "@me:ex")
  length(out$to_device)
}
}
}
