% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_relogin}
\alias{mx_client_relogin}
\title{Re-login with stored credentials and refresh the saved token}
\usage{
mx_client_relogin(client, save = TRUE)
}
\arguments{
\item{client}{Matrix client config with \code{password}.}

\item{save}{Logical. Persist the refreshed config (default TRUE).}
}
\value{
The refreshed \code{"mx_client_config"}.
}
\description{
Uses the password persisted in the client config to obtain a fresh
access token for the \emph{same} device (reusing
\code{client$device_id}, so an E2EE device identity survives the
refresh), then saves the updated config. Typical use is recovering
from an invalidated token; see \code{\link{mx_with_relogin}} for the
catch-and-retry wrapper.
}
\examples{
\dontrun{
# Needs a live homeserver and a stored password.
client <- mx_client_relogin(mx_client_load("myapp"))
}
}
