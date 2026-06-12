% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_session}
\alias{mx_client_session}
\title{Build an mx.api session from a client config}
\usage{
mx_client_session(client)
}
\arguments{
\item{client}{Named list or \code{"mx_client_config"} with \code{server},
\code{token}, \code{user_id}, and \code{device_id}.}
}
\value{
An \code{"mx_session"} from \pkg{mx.api}.
}
\description{
Build an mx.api session from a client config
}
\examples{
s <- mx_client_session(list(server = "https://matrix.example.org",
                            token = "syt_example",
                            user_id = "@bot:example.org",
                            device_id = "DEVICEID"))
class(s)
}
