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
\examples{
\dontrun{
# Requires a live Matrix account and this device's existing crypto store.
# Stop other processes using the device first. Never substitute a new store.
client <- mx_client_load(path = Sys.getenv("MATRIX_CONFIG"))
store <- Sys.getenv("MATRIX_CRYPTO_STORE")
stopifnot(nzchar(store), file.exists(file.path(store, "account.pickle")))
account <- mx_crypto_account(store)
public <- mx_crypto_cross_signing_bootstrap(client, account, store,
    password = Sys.getenv("MATRIX_ACCOUNT_PASSWORD"))
# The encrypted private keys remain local; the return value contains key ids.
public$master
}
}
