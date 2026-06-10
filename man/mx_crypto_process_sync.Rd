% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_process_sync}
\alias{mx_crypto_process_sync}
\title{Process a sync response: store room keys, decrypt room events}
\usage{
mx_crypto_process_sync(account, sessions, sync_resp, self_curve25519,
                       self_id = NULL)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set.}

\item{sync_resp}{Parsed \code{/sync} response.}

\item{self_curve25519}{Character. This device's Curve25519 key.}

\item{self_id}{Character or NULL. This user's Matrix id, for
\code{is_self} tagging.}
}
\value{
List with \code{events} (decrypted, normalized) and the updated
  \code{sessions}.
}
\description{
Handles inbound to-device \code{m.room.encrypted} (Olm) messages,
storing any \code{m.room_key} as an inbound Megolm session, then
decrypts \code{m.room.encrypted} timeline events whose session is
known. Returns normalized text events in the same shape as
\code{mx_extract_text_events()}, plus the updated session set.
}
\examples{
\donttest{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
  acct <- mx.crypto::mxc_account_new()
  res <- mx_crypto_process_sync(acct, mx_crypto_sessions_new(),
    list(to_device = list(events = list()), rooms = list(join = list())),
    mx.crypto::mxc_account_identity_keys(acct)$curve25519)
  length(res$events)
}
}
}
