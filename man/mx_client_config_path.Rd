% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_config_path}
\alias{mx_client_config_path}
\title{Path to a Matrix client config file}
\usage{
mx_client_config_path(app = "mx.client", env_var = NULL)
}
\arguments{
\item{app}{Character. Application namespace for \code{tools::R_user_dir()}.}

\item{env_var}{Character or NULL. Override environment variable name.}
}
\value{
Character path.
}
\description{
Resolves the config path for an application that uses mx.client. The
default environment variable is derived from \code{app}; for example,
\code{app = "corteza"} honors \code{CORTEZA_MATRIX_CONFIG}.
}
\examples{
mx_client_config_path("myapp")
}
