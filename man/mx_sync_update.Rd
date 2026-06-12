% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sync_update}
\alias{mx_sync_update}
\title{Sync once and update the stored cursor}
\usage{
mx_sync_update(client, timeout = 0L, filter = NULL, save = TRUE, path = NULL,
               app = NULL)
}
\arguments{
\item{client}{Matrix client config.}

\item{timeout}{Integer long-poll timeout in milliseconds.}

\item{filter}{Character or NULL. Matrix sync filter.}

\item{save}{Logical. Persist the updated client config.}

\item{path}{Character or NULL. Save destination.}

\item{app}{Character or NULL. Application namespace for default saves.}
}
\value{
List with \code{sync}, \code{client}, and \code{first_run}.
}
\description{
Calls \code{mx.api::mx_sync()} using \code{client$sync_token}, stores
the returned \code{next_batch} in a returned client object, and
optionally saves it back to disk.
}
\examples{
\dontrun{
# Needs a live homeserver session.
client <- mx_client_load("myapp")
res <- mx_sync_update(client, timeout = 30000L)
events <- mx_extract_text_events(res$sync, client$user_id)
}
}
