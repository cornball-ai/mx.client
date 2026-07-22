% tinyrox says don't edit this manually, but it can't stop you!
\name{print.mx_client_config}
\alias{print.mx_client_config}
\title{Print a Matrix client config}
\usage{
\method{print}{mx_client_config}(x, ...)
}
\arguments{
\item{x}{An \code{mx_client_config}, as returned by
\code{mx_client_load()} or \code{mx_client_from_config()}.}

\item{...}{Ignored.}
}
\value{
\code{x}, invisibly.
}
\description{
Prints the config field by field with credentials masked, so that an
interactive session, a screenshot, or a pasted bug report does not
leak the access token or password. Secret fields show whether they
are set (\code{<hidden>}) or empty (\code{<unset>}) without showing
the value. Use \code{unclass(x)} or \code{str(unclass(x))} when the
raw credentials are genuinely needed.
}
\examples{
cfg <- mx_client_from_config(list(server = "https://matrix.example.org",
                                  token = "syt_secret_value",
                                  user_id = "@bot:example.org",
                                  device_id = "DEVICEID"))
cfg
}
