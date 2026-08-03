% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_known_devices}
\alias{mx_crypto_known_devices}
\title{List the devices (and identity keys) of some users}
\usage{
mx_crypto_known_devices(client, user_ids)
}
\arguments{
\item{client}{Matrix client config.}

\item{user_ids}{Character vector of Matrix user ids.}
}
\value{
List of verified devices, each \code{list(user_id, device_id,
  curve25519, ed25519)}.
}
\description{
Queries \code{/keys/query} and flattens the result to a list of devices.
}
\details{
Devices are returned only if their Ed25519 self-signature verifies
against the identity the homeserver claims for them. A device that
fails is dropped with a warning naming it, and the remaining devices
are still returned: one bad device must not make a room unusable.

}
\examples{
\dontrun{
mx_crypto_known_devices(client, "@bob:example.org")
}
}
