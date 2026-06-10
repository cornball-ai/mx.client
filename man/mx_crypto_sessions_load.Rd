% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_sessions_load}
\alias{mx_crypto_sessions_load}
\title{Load a session set from the crypto store}
\usage{
mx_crypto_sessions_load(store_dir)
}
\arguments{
\item{store_dir}{Character. Crypto store directory.}
}
\value{
A session set (empty if nothing is stored yet).
}
\description{
Load a session set from the crypto store
}
\examples{
\donttest{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
  s <- mx_crypto_sessions_load(file.path(tempfile(), "crypto"))
}
}
}
