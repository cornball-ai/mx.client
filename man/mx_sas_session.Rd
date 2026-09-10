% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_session}
\alias{mx_sas_session}
\title{Create an in-memory Matrix SAS transaction}
\usage{
mx_sas_session(
  user_id,
  device_id,
  keys,
  peer_user_id,
  peer_device_id,
  peer_keys,
  transaction_id,
  room_id = NULL,
  initiator = FALSE,
  now = Sys.time()
)
}
\arguments{
\item{user_id}{This account's Matrix user id.}

\item{device_id}{This account's device id.}

\item{keys}{Named list of this device's Ed25519 key and locally trusted
master key. Names are ed25519:device_id and ed25519:master_public_key.}

\item{peer_user_id}{The selected peer user id.}

\item{peer_device_id}{The selected peer device id.}

\item{peer_keys}{Named list containing the peer device and master public
keys fetched and validated before the handshake. SAS authenticates this
exact snapshot, not later replacements from a homeserver.}

\item{transaction_id}{Initial request event id for room verification,
or the initial to-device request's transaction_id.}

\item{room_id}{Room id, or NULL for to-device verification.}

\item{initiator}{TRUE if this device sent the initial request.}

\item{now}{Current time. Injectable for deterministic timeout tests.}
}
\value{
An opaque in-memory transaction. Use mx_sas_status() for display.
}
\description{
Holds a fixed snapshot of both parties' device and master public keys.
Feed this object events from the application's existing event consumer;
this function does not start sync, send messages, or record trust.
Ephemeral state cannot be persisted. Restart interrupted transactions
with a new request id and new session. Only modern SAS algorithms are used.
}
