% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_process_sync}
\alias{mx_crypto_process_sync}
\title{Process a sync response: store room keys, decrypt room events}
\usage{
mx_crypto_process_sync(
  account,
  sessions,
  sync_resp,
  self_curve25519,
  self_id = NULL,
  devices = NULL,
  self_device_id = NULL
)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set.}

\item{sync_resp}{Parsed \code{/sync} response.}

\item{self_curve25519}{Character. This device's Curve25519 key.}

\item{self_id}{Character or NULL. This user's Matrix id, for
\code{is_self} tagging and as the recipient of key requests.}

\item{devices}{List of verified devices from
\code{mx_crypto_known_devices()}, or NULL. Room keys arrive over Olm
carrying a claimed sender, and anyone who can reach this device can
send one, so the claim is only worth something once it is matched
against a device whose \code{device_keys} verified. Without this
list peers' decrypted events report \code{sender_verified = FALSE}:
they still decrypt, but nothing attests to who sent them. Own echoes
can be verified against the locally retained outbound session. Forwarded
keys require this user's cross-signed devices, queried with a trusted
local \code{self_master_key}; they never verify the original sender.}

\item{self_device_id}{Character or NULL. This device id. Both this and
\code{self_id} are required to create room-key requests.}
}
\value{
List with \code{events} (decrypted, normalized), updated
  \code{sessions}, unsent \code{key_requests}, matching
  \code{key_request_cancellations}, and \code{incoming_key_requests}
  for a policy-aware sharing layer to inspect.
}
\description{
Handles inbound to-device \code{m.room.encrypted} (Olm) messages,
storing direct \code{m.room_key} events and requested
\code{m.forwarded_room_key} events as inbound Megolm sessions. It then
decrypts timeline events whose session is known and queues stable,
retryable \code{m.room_key_request} messages for missing sessions. The
caller sends those requests to this user's other devices.
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
