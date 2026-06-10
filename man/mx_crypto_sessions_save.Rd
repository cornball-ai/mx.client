% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_sessions_save}
\alias{mx_crypto_sessions_save}
\title{Persist a session set to the crypto store}
\usage{
mx_crypto_sessions_save(sessions, store_dir)
}
\arguments{
\item{sessions}{A session set.}

\item{store_dir}{Character. Crypto store directory.}
}
\value{
The path written, invisibly.
}
\description{
Pickles every live session (encrypted at rest with the store key) into
\code{sessions.json}. Reload with \code{mx_crypto_sessions_load()}.
}
\examples{
\donttest{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
  dir <- file.path(tempfile(), "crypto")
  mx_crypto_sessions_save(mx_crypto_sessions_new(), dir)
}
}
}
