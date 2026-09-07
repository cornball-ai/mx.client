% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_send_key_requests}
\alias{mx_crypto_send_key_requests}
\title{Send queued Matrix room-key requests or cancellations}
\usage{
mx_crypto_send_key_requests(client, requests)
}
\arguments{
\item{client}{Matrix client config.}

\item{requests}{A list of request/cancellation descriptors returned by
[mx_crypto_process_sync()].}
}
\value{
The endpoint responses, invisibly.
}
\description{
Sends each descriptor returned by [mx_crypto_process_sync()] as an
unencrypted \code{m.room_key_request} to every device of this user. The
receiving clients apply their own verified-device sharing policy.
}
\examples{
\dontrun{
mx_crypto_send_key_requests(client, result$key_requests)
}
}
