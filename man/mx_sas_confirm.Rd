% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_confirm}
\alias{mx_sas_confirm}
\title{Confirm or reject the displayed Matrix SAS}
\usage{
mx_sas_confirm(sas, matches, now = Sys.time())
}
\arguments{
\item{sas}{An in-memory SAS transaction displaying a SAS.}

\item{matches}{One explicit TRUE or FALSE, without a default.}

\item{now}{Current time.}
}
\value{
The transaction, invisibly.
}
\description{
Call only after the human compares the display through a trusted channel.
TRUE queues MACs for this device and its master key. Both a valid peer MAC
and local confirmation are required before the phase becomes verified.
This alone does not upload cross-signing signatures.
}
