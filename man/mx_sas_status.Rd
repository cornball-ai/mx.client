% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_status}
\alias{mx_sas_status}
\title{Inspect a Matrix SAS verification transaction}
\usage{
mx_sas_status(sas)
}
\arguments{
\item{sas}{An in-memory SAS transaction.}
}
\value{
A list with identities, phase, comparison values, local confirmation,
  peer MAC validity, local trust status, peer completion, and cancellation code.
  cancel_detail identifies a locally diagnosed missing peer master proof.
}
\description{
Display codes only on the operator's trusted console, never in the Matrix
conversation being verified. A verified SAS is distinct from a recorded
local trust signature and from the peer's completion acknowledgement.
}
