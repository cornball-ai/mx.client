% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_encrypt_event}
\alias{mx_crypto_encrypt_event}
\title{Encrypt event content for a room (Megolm)}
\usage{
mx_crypto_encrypt_event(
  megolm_out,
  content,
  room_id,
  sender_curve25519,
  device_id,
  event_type = "m.room.message"
)
}
\arguments{
\item{megolm_out}{An outbound Megolm session.}

\item{content}{Named list. The plaintext event content (e.g. an
\code{m.room.message}).}

\item{room_id}{Character. Room id.}

\item{sender_curve25519}{Character. This device's Curve25519 key.}

\item{device_id}{Character. This device's id.}

\item{event_type}{Inner Matrix event type. Defaults to m.room.message;
verification replies use their m.key.verification.* event type.}
}
\value{
A named list: \code{m.room.encrypted} content.
}
\description{
Returns the \code{m.room.encrypted} content to send as the event body.
}
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    account <- mx.crypto::mxc_account_new()
    sender <- mx.crypto::mxc_account_identity_keys(account)$curve25519
    megolm_out <- mx.crypto::mxc_megolm_outbound_new()
    enc <- mx_crypto_encrypt_event(megolm_out,
        list(msgtype = "m.text", body = "Hello"),
        "!room:example.org", sender, "ALICE")
    stopifnot(identical(enc$algorithm, "m.megolm.v1.aes-sha2"))
}
}
