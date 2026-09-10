% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_cancel}
\alias{mx_sas_cancel}
\title{Cancel a SAS transaction without granting trust}
\usage{
mx_sas_cancel(sas, code = "m.user")
}
\arguments{
\item{sas}{An in-memory SAS transaction.}

\item{code}{Matrix cancellation code.}
}
\value{
The transaction, invisibly. At most one cancellation is queued.
}
\description{
Cancel a SAS transaction without granting trust
}
