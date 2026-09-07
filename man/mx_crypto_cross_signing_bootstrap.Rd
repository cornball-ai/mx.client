% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_cross_signing_bootstrap}
\alias{mx_crypto_cross_signing_bootstrap}
\title{Bootstrap and sign this Matrix device's cross-signing identity}
\usage{
mx_crypto_cross_signing_bootstrap(
  client,
  device_account,
  store_dir,
  password = NULL,
  auth = NULL
)
}
\arguments{
\item{client}{Matrix client config.}

\item{device_account}{This device's persisted Olm account.}

\item{store_dir}{Character. Crypto store directory.}

\item{password}{Character or NULL. Account password used only for UIA.}

\item{auth}{Completed Matrix UIA object or NULL.}
}
\value{
Public master, self-signing and user-signing key ids, invisibly.
}
\description{
Creates master, self-signing and user-signing keys only when neither the
local crypto store nor homeserver already has an identity. Existing local
keys are reused; a server/local mismatch aborts instead of resetting the
identity. The current device signs the master key and the self-signing key
signs the current device.
Valid signatures already returned by the homeserver are not re-uploaded.
}
