% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_service_url}
\alias{mx_call_service_url}
\title{Find the LiveKit JWT service for a room's call}
\usage{
mx_call_service_url(client, members = list())
}
\arguments{
\item{client}{Matrix client config.}

\item{members}{Current members from \code{\link{mx_call_members}}.}
}
\value{
The service URL, a string.
}
\description{
Tries, in order, the services the current call members advertise in
their memberships, the homeserver's RTC transports
(\code{mx.api::mx_rtc_transports()}), and the
\code{org.matrix.msc4143.rtc_foci} entry of the server's client
well-known file.
}
\examples{
\dontrun{
mx_call_service_url(client, members)
}
}
