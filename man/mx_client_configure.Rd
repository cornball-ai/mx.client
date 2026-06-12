% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_configure}
\alias{mx_client_configure}
\title{Configure and save a Matrix client}
\usage{
mx_client_configure(server, user, password, room, app = "mx.client",
                    path = NULL, device_id = NULL, extra = list())
}
\arguments{
\item{server}{Character. Homeserver base URL.}

\item{user}{Character. Matrix user localpart or full MXID.}

\item{password}{Character. Account password.}

\item{room}{Character. Room ID or alias to join.}

\item{app}{Character. Application namespace.}

\item{path}{Character or NULL. Explicit destination path.}

\item{device_id}{Character or NULL. Existing device id to reuse.}

\item{extra}{Named list. Additional fields to save.}
}
\value{
Saved \code{"mx_client_config"}, invisibly.
}
\description{
Logs in with \pkg{mx.api}, joins or records the target room, and writes
a reusable local config. Extra fields are merged into the saved config
so applications can persist their own defaults without reimplementing
login.
}
\examples{
\dontrun{
# Needs a live homeserver and account credentials.
mx_client_configure("https://matrix.example.org", "bot", "secret",
                    room = "#general:example.org", app = "myapp")
}
}
