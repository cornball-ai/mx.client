% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_poll}
\alias{mx_call_poll}
\title{Sync once and poll the media of a call}
\usage{
mx_call_poll(call, timeout = 1, media_timeout = 0.1)
}
\arguments{
\item{call}{An \code{"mx_call"}.}

\item{timeout}{Seconds to wait for the sync long poll.}

\item{media_timeout}{Seconds to wait in the media poll.}
}
\value{
The LiveKit events from \code{livekitr::lk_poll()}, or an
  empty list when the call has no media session.
}
\description{
One iteration of a call loop for programs with no sync loop of their
own: syncs with \code{\link{mx_sync_update}}, applies the response with
\code{\link{mx_call_handle}}, and polls the LiveKit session with
\code{livekitr::lk_poll()}, which is where audio callbacks run.
}
