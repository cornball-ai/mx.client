% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_start}
\alias{mx_sas_start}
\title{Begin the SAS key agreement after request negotiation}
\usage{
mx_sas_start(sas, now = Sys.time())
}
\arguments{
\item{sas}{An in-memory SAS transaction in the ready phase.}

\item{now}{Current time.}
}
\value{
The transaction, invisibly. A start event is queued, not sent.
}
\description{
Begin the SAS key agreement after request negotiation
}
