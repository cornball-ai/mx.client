% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_mark_key_requests_sent}
\alias{mx_crypto_mark_key_requests_sent}
\title{Mark successfully transmitted room-key requests}
\usage{
mx_crypto_mark_key_requests_sent(sessions, requests)
}
\arguments{
\item{sessions}{An E2EE session set.}

\item{requests}{Request descriptors sent successfully.}
}
\value{
The updated session set.
}
\description{
Updates durable request records after transport succeeds. Requests remain
queued until marked, allowing a failed send to retry on a later poll even
after the original encrypted event has left the sync timeline.
}
