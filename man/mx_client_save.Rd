% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_save}
\alias{mx_client_save}
\title{Save a Matrix client config}
\usage{
mx_client_save(client, app = NULL, path = NULL)
}
\arguments{
\item{client}{Named list or \code{"mx_client_config"}.}

\item{app}{Character or NULL. Application namespace.}

\item{path}{Character or NULL. Destination path.}
}
\value{
The saved config, invisibly.
}
\description{
Writes JSON with mode 0600.
}
