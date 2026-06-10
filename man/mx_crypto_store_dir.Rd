% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_store_dir}
\alias{mx_crypto_store_dir}
\title{Directory holding this client's encryption state}
\usage{
mx_crypto_store_dir(app = "mx.client", path = NULL)
}
\arguments{
\item{app}{Character. Application namespace.}

\item{path}{Character or NULL. Explicit store directory.}
}
\value{
Character directory path.
}
\description{
The crypto store keeps the pickled Olm account, the 32-byte key that
encrypts those pickles at rest, and (later) per-peer Olm and per-room
Megolm sessions. It lives beside the JSON config under
\code{tools::R_user_dir()}.
}
\examples{
mx_crypto_store_dir("myapp", path = tempfile())
}
