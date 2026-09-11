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
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    example("mx_sas_receive", package = "mx.client", echo = FALSE)
    # Demonstrate declining the comparison. No identity trust is granted.
    mx_sas_confirm(alice, matches = FALSE)
    stopifnot(identical(mx_sas_status(alice)$cancel_code, "m.mismatched_sas"),
        !mx_sas_status(alice)$local_trust_recorded)
}
}
