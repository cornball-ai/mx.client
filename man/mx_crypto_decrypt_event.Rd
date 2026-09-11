% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_decrypt_event}
\alias{mx_crypto_decrypt_event}
\title{Decrypt an m.room.encrypted event (Megolm)}
\usage{
mx_crypto_decrypt_event(inbound_session, encrypted)
}
\arguments{
\item{inbound_session}{An inbound Megolm session for the event's
\code{session_id}.}

\item{encrypted}{The \code{m.room.encrypted} event content.}
}
\value{
The decrypted event payload (a parsed list).
}
\description{
Decrypt an m.room.encrypted event (Megolm)
}
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    account <- mx.crypto::mxc_account_new()
    sender <- mx.crypto::mxc_account_identity_keys(account)$curve25519
    megolm_out <- mx.crypto::mxc_megolm_outbound_new()
    key <- mx.crypto::mxc_megolm_outbound_info(megolm_out)$session_key
    inb <- mx_crypto_inbound_session(key)
    enc <- mx_crypto_encrypt_event(megolm_out,
        list(msgtype = "m.text", body = "Hello"),
        "!room:example.org", sender, "ALICE")
    ev <- mx_crypto_decrypt_event(inb, enc)
    stopifnot(identical(ev$content$body, "Hello"))
}
}
