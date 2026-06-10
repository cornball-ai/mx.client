% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_claim_otks}
\alias{mx_crypto_claim_otks}
\title{Claim a one-time key for each device}
\usage{
mx_crypto_claim_otks(client, devices)
}
\arguments{
\item{client}{Matrix client config.}

\item{devices}{List of devices from \code{mx_crypto_known_devices()}.}
}
\value{
The devices with an \code{otk} field added where one was
  claimed.
}
\description{
Calls \code{/keys/claim} and attaches the claimed key to each device as
\code{$otk}, ready for \code{mx_crypto_encrypt_for_devices()}.
}
\examples{
\dontrun{
devs <- mx_crypto_claim_otks(client, mx_crypto_known_devices(client, uid))
}
}
