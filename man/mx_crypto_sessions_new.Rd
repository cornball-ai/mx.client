% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_sessions_new}
\alias{mx_crypto_sessions_new}
\title{Create an empty E2EE session set}
\usage{
mx_crypto_sessions_new()
}
\value{
A session set: named lists \code{olm}, \code{olm_in},
  \code{megolm_out}, \code{megolm_in}.
}
\description{
Create an empty E2EE session set
}
\examples{
s <- mx_crypto_sessions_new()
names(s)
}
