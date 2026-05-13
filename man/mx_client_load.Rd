% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_load}
\alias{mx_client_load}
\title{Load a Matrix client config}
\usage{
mx_client_load(app = "mx.client", path = NULL,
               legacy_path = mx_client_legacy_config_path(app), env_var = NULL)
}
\arguments{
\item{app}{Character. Application namespace.}

\item{path}{Character or NULL. Explicit config path.}

\item{legacy_path}{Character or NULL. Backward-compatible fallback path.}

\item{env_var}{Character or NULL. Override environment variable name.}
}
\value{
An \code{"mx_client_config"} object.
}
\description{
Reads a JSON config. If \code{path} or the derived environment variable
is explicit, that path is authoritative. Otherwise \code{legacy_path}
is used as a compatibility fallback when present.
}
