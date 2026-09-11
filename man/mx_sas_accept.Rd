% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_accept}
\alias{mx_sas_accept}
\title{Accept an incoming SAS verification request}
\usage{
mx_sas_accept(sas, now = Sys.time())
}
\arguments{
\item{sas}{An in-memory SAS transaction.}

\item{now}{Current time.}
}
\value{
The transaction, invisibly. A ready event is queued, not sent.
}
\description{
Accept an incoming SAS verification request
}
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    example("mx_sas_session", package = "mx.client", echo = FALSE)
    mx_sas_accept(bob)
    stopifnot(identical(mx_sas_status(bob)$phase, "ready"))
}
}
