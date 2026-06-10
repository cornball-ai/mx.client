% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_device_keys}
\alias{mx_crypto_device_keys}
\title{Build a signed device_keys object for upload}
\usage{
mx_crypto_device_keys(account, user_id, device_id)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{user_id}{Character. Full Matrix user id.}

\item{device_id}{Character. This device's id.}
}
\value{
A named list ready to upload.
}
\description{
Produces the \code{device_keys} structure \code{/keys/upload} expects:
the device's public identity keys plus an Ed25519 signature over their
canonical JSON. Hand the result to \code{mx.api::mx_keys_upload()}.
}
\examples{
\dontrun{
dk <- mx_crypto_device_keys(acct, "@bot:example.org", "DEVICEID")
mx.api::mx_keys_upload(session, device_keys = dk)
}
}
