% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_handle}
\alias{mx_call_handle}
\title{Feed a sync response to a call}
\usage{
mx_call_handle(call, sync, processed = NULL)
}
\arguments{
\item{call}{An \code{"mx_call"}.}

\item{sync}{A parsed \code{/sync} response.}

\item{processed}{The result of \code{mx_crypto_process_sync()} on
\code{sync}, or NULL to have it run here (its \code{sessions} are
then kept in \code{call$sessions}).}
}
\value{
A list of what changed: \code{keys}, the identities whose
  keys were received, and \code{members}, the current members when
  membership changed (NULL otherwise).
}
\description{
Applies what a \code{/sync} response means for the call: peers' media
keys from the decrypted to-device events, membership changes (which
may rotate and resend our key), and the hourly refresh of our own
membership. Call it with every sync while in the call. When the
application already runs \code{\link{mx_crypto_process_sync}} on the
response, pass its result as \code{processed} so to-device events
are not decrypted twice.
}
