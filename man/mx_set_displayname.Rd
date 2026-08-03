% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_set_displayname}
\alias{mx_set_displayname}
\title{Set the account's profile display name}
\usage{
mx_set_displayname(client, name, save = TRUE)
}
\arguments{
\item{client}{Matrix client config.}

\item{name}{Character. New display name.}

\item{save}{Logical. On a relogin, persist the refreshed token to the
client's config path (see \code{\link{mx_client_relogin}}).}
}
\value{
TRUE, invisibly.
}
\description{
Client-level wrapper over \code{mx.api::mx_set_displayname()}: builds
the session from the client config and retries once through
\code{\link{mx_with_relogin}} when the homeserver rejects a rotated
token. The display name is account-global and shows in the sender
line of every message the account posts.
}
\examples{
\dontrun{
# A real rename needs a live homeserver session:
client <- mx_client_load("myapp")
mx_set_displayname(client, "mybot (maintenance)")
}
}
