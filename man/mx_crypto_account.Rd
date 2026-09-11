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
Legacy raw pickles remain readable. New saves use a version-1 JSON
envelope around the encrypted pickle; unknown versions are rejected.
Loading does not migrate the file. Clients older than 0.2.0.11 cannot
read the new envelope, so back up the store before upgrading or downgrading.
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
