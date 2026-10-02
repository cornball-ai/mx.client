% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_join}
\alias{mx_call_join}
\title{Join a MatrixRTC call}
\usage{
mx_call_join(
  client,
  account,
  sessions,
  room_id,
  intent = "voice",
  store_dir = NULL,
  connect = TRUE,
  service_url = NULL
)
}
\arguments{
\item{client}{Matrix client config.}

\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set.}

\item{room_id}{The room whose call to join.}

\item{intent}{\code{"voice"} or \code{"video"}, what the membership
announces.}

\item{store_dir}{Character or NULL. Where the updated crypto sessions
are saved after each key send.}

\item{connect}{Join the LiveKit room now? \code{FALSE} does everything
on the Matrix side only.}

\item{service_url}{Character or NULL. The LiveKit JWT service to use
instead of discovering one.}
}
\value{
An object of class \code{"mx_call"}: an environment holding
  the \code{client} and \code{sessions} (both updated as the call
  runs), the LiveKit \code{session} from \pkg{livekitr} (or NULL), this
  device's LiveKit \code{identity}, the current \code{members}, and
  the media \code{token}.
}
\description{
Joins the call of a room the way Element Call and FluffyChat do:
finds the LiveKit JWT service, trades an OpenID token for a media
token, announces this device's membership as a state event, makes a
media key and sends it Olm-encrypted to every device already in the
call, and, with \code{connect = TRUE}, joins the LiveKit room through
\pkg{livekitr} with end-to-end encryption on. The returned call must
then be driven with \code{\link{mx_call_handle}} (or
\code{\link{mx_call_poll}}) and ended with \code{\link{mx_call_leave}}.
}
\examples{
\dontrun{
call <- mx_call_join(client, acct, sessions, "!room:example.org",
                     store_dir = store)
livekitr::lk_on_audio(call$session, function(pcm, info) {
    cat(info$identity, "spoke\n")
})
repeat mx_call_poll(call)
}
}
