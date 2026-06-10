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
\dontrun{
ev <- mx_crypto_decrypt_event(inb, encrypted_content)
ev$content$body
}
}
