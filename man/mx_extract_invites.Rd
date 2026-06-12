% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_invites}
\alias{mx_extract_invites}
\title{Extract pending invite room ids from a sync response}
\usage{
mx_extract_invites(sync_resp)
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}
}
\value{
Character vector of invited room ids.
}
\description{
Extract pending invite room ids from a sync response
}
\examples{
sync_resp <- list(rooms = list(invite = list("!inv:example.org" = list())))
mx_extract_invites(sync_resp)
}
