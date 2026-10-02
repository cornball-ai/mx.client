% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_members}
\alias{mx_call_members}
\title{Active call memberships in a room's state}
\usage{
mx_call_members(state, now = Sys.time())
}
\arguments{
\item{state}{List of state events.}

\item{now}{The current time.}
}
\value{
A list of members, each \code{list(user_id, device_id,
  identity, membership_id, service_urls, expires_at)}, where
  \code{identity} is the member's LiveKit participant identity
  \code{"<user>:<device>"} and \code{service_urls} the LiveKit JWT
  services it prefers.
}
\description{
Reads the \code{org.matrix.msc3401.call.member} state events out of a
room's full state (\code{mx.api::mx_room_state()}) and keeps the ones
that count as in the call: non-empty content, a LiveKit focus, and an
expiry (\code{created_ts}, or \code{created_at}, or the event's own
timestamp, plus \code{expires}, default 4 hours) still in the future.
}
\examples{
state <- list(list(type = "org.matrix.msc3401.call.member",
    sender = "@alice:example.org", origin_server_ts = 1e12,
    content = list(application = "m.call", device_id = "PHONE",
        focus_active = list(type = "livekit"),
        foci_preferred = list(list(type = "livekit",
            livekit_service_url = "https://jwt.example.org")))))
mx_call_members(state, now = as.POSIXct(1e9, origin = "1970-01-01"))
}
