% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_with_relogin}
\alias{mx_with_relogin}
\title{Run a client operation, re-logging in once on an expired token}
\usage{
mx_with_relogin(client, fn, save = TRUE)
}
\arguments{
\item{client}{Matrix client config with \code{password}.}

\item{fn}{Function taking a client config.}

\item{save}{Logical. Persist the refreshed config on relogin.}
}
\value{
\code{fn}'s return value.
}
\description{
Calls \code{fn(client)}; if it fails with the server's invalid-token
error (\code{M_UNKNOWN_TOKEN}, signalled as a classed condition by
mx.api >= 0.3.0), re-logs in via \code{\link{mx_client_relogin}} and
retries once with the refreshed client. Any other error propagates.
}
\examples{
\dontrun{
mx_with_relogin(client, function(cl) {
    mx_send_text(cl, "still here after a token rotation")
})
}
}
