% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_poll}
\alias{mx_call_poll}
\title{Poll the media of a call, then sync once}
\usage{
mx_call_poll(call, media_timeout = 0.5, timeout = 0)
}
\arguments{
\item{call}{An \code{"mx_call"}.}

\item{media_timeout}{Seconds to wait in the media poll.}

\item{timeout}{Seconds to let the sync long poll wait.}
}
\value{
The LiveKit events from \code{livekitr::lk_poll()}, or an
  empty list when the call has no media session.
}
\description{
One iteration of a call loop for programs with no sync loop of their
own: polls the LiveKit session with \code{livekitr::lk_poll()}, which
is where audio callbacks run, for up to \code{media_timeout} seconds
(it returns as soon as media events arrive, so the wait is short while
someone speaks), then syncs with \code{\link{mx_sync_update}} and
applies the response with \code{\link{mx_call_handle}}.
}
\details{
Audio callbacks only run while this process polls, so the sync must
not block for long: the default \code{timeout = 0} asks the homeserver
to answer at once. Not every homeserver complies: Tuwunel 1.9 holds an
incremental sync that has nothing new for 5 s whatever the timeout,
and returns at once only when something happened. Frames that arrive
meanwhile wait in \pkg{livekitr}'s native queue, so nothing is lost,
but they reach the callback late. A program that needs prompt audio
on such a server should sync from another process or thread.

}
