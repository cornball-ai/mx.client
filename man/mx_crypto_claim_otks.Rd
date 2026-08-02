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
  claimed and verified.
}
\description{
Calls \code{/keys/claim} and attaches the claimed key to each device as
\code{$otk}, ready for \code{mx_crypto_encrypt_for_devices()}.
}
\details{
Each claimed key's signature is checked against the device's Ed25519
key, which must itself have come from a verified \code{device_keys}
(that is, from \code{mx_crypto_known_devices()}). A key that fails is
dropped with a warning and its device comes back with no \code{otk}.

}
\examples{
\dontrun{
devs <- mx_crypto_claim_otks(client, mx_crypto_known_devices(client, uid))
}
}
