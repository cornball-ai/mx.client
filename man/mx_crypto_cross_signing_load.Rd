% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_cross_signing_load}
\alias{mx_crypto_cross_signing_load}
\title{Load locally persisted Matrix cross-signing keys}
\usage{
mx_crypto_cross_signing_load(store_dir)
}
\arguments{
\item{store_dir}{Character. Crypto store directory.}
}
\value{
A list containing master, self-signing and user-signing key handles,
  or NULL.
}
\description{
Returns NULL when this crypto store has never bootstrapped a cross-signing
identity. A present but malformed store is an error: generating over it
would silently reset the user's Matrix identity.
}
