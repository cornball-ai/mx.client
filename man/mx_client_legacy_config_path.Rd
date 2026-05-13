% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_client_legacy_config_path}
\alias{mx_client_legacy_config_path}
\title{Legacy Matrix config path for an application}
\usage{
mx_client_legacy_config_path(app = "mx.client")
}
\arguments{
\item{app}{Character. Application namespace.}
}
\value{
Character path or NULL.
}
\description{
Currently only \code{app = "corteza"} has a historical path:
\code{~/.corteza/matrix.json}.
}
