% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_accept_invites}
\alias{mx_accept_invites}
\title{Accept pending Matrix room invites}
\usage{
mx_accept_invites(client, invites)
}
\arguments{
\item{client}{Matrix client config.}

\item{invites}{Character vector of room ids.}
}
\value{
Character vector of joined room ids.
}
\description{
Accept pending Matrix room invites
}
\examples{
\dontrun{
# Needs a live homeserver session.
client <- mx_client_load("myapp")
res <- mx_sync_update(client)
mx_accept_invites(res$client, mx_extract_invites(res$sync))
}
}
