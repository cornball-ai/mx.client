% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_account_save}
\alias{mx_crypto_account_save}
\title{Persist an Olm account to the store}
\usage{
mx_crypto_account_save(account, store_dir)
}
\arguments{
\item{account}{An mx.crypto account handle.}

\item{store_dir}{Character. Crypto store directory.}
}
\value{
The pickle path, invisibly.
}
\description{
Persist an Olm account to the store
}
\examples{
\dontrun{
mx_crypto_account_save(acct, mx_crypto_store_dir("corteza"))
}
}
