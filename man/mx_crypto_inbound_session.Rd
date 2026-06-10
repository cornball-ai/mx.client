% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_inbound_session}
\alias{mx_crypto_inbound_session}
\title{Build an inbound Megolm session from a shared room key}
\usage{
mx_crypto_inbound_session(session_key)
}
\arguments{
\item{session_key}{Character. The \code{session_key} from an
\code{m.room_key} event.}
}
\value{
An inbound Megolm session.
}
\description{
Build an inbound Megolm session from a shared room key
}
\examples{
\dontrun{
inb <- mx_crypto_inbound_session(ev$content$session_key)
}
}
