% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_known_devices}
\alias{mx_crypto_known_devices}
\title{List the devices (and identity keys) of some users}
\usage{
mx_crypto_known_devices(client, user_ids, strict = FALSE)
}
\arguments{
\item{client}{Matrix client config.}

\item{user_ids}{Character vector of Matrix user ids.}

\item{strict}{Logical. Treat a \code{failures} map as an error rather
than a warning.}
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

\code{/keys/query} answers 200 with a \code{failures} map when it could
not reach a server, and returns whatever it did manage. That is not the
same as a user having no devices, so it is never silent: by default it
warns, and with \code{strict = TRUE} it is an error. Encrypting to a
user whose devices could not be listed is how a message ends up
readable by nobody, so the send path asks for strict.

}
\examples{
\dontrun{
mx_crypto_known_devices(client, "@bob:example.org")
}
}
