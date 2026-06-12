% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_account}
\alias{mx_crypto_account}
\title{Load or create this client's Olm account}
\usage{
mx_crypto_account(store_dir)
}
\arguments{
\item{store_dir}{Character. Crypto store directory.}
}
\value{
An mx.crypto account handle.
}
\description{
Unpickles \code{account.pickle} from the store, or mints a fresh
account and persists it. The account holds the device's long-lived
Curve25519/Ed25519 identity keys.
}
\examples{
\donttest{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
  store <- mx_crypto_store_dir("myapp", path = tempfile())
  acct <- mx_crypto_account(store)
  unlink(store, recursive = TRUE)
}
}
}
