% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_room_lookup_by_name}
\alias{mx_room_lookup_by_name}
\title{Look up a joined room by display name}
\usage{
mx_room_lookup_by_name(client, name)
}
\arguments{
\item{client}{Matrix client config.}

\item{name}{Character room name.}
}
\value{
Room id, or NULL when no joined room has that name.
}
\description{
Look up a joined room by display name
}
\examples{
\dontrun{
# Needs a live homeserver session.
mx_room_lookup_by_name(mx_client_load("myapp"), "general")
}
}
