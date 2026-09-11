% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_outgoing}
\alias{mx_sas_outgoing}
\title{Read or acknowledge queued SAS protocol messages}
\usage{
mx_sas_outgoing(sas, acknowledge = character())
}
\arguments{
\item{sas}{An in-memory SAS transaction.}

\item{acknowledge}{Character vector of successfully sent queue ids.}
}
\value{
A list of pending envelopes, containing type, content, destination,
  and a stable transport id. No private key material is included.
}
\description{
Send outside any cryptographic state commit window. Acknowledge an id
only after transport succeeds. Retries retain the same id and payload.
Never display SAS codes in the Matrix conversation being verified.
}
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    example("mx_sas_session", package = "mx.client", echo = FALSE)
    mx_sas_accept(bob)
    pending <- mx_sas_outgoing(bob)
    stopifnot(length(pending) == 1L,
        identical(mx_sas_outgoing(bob), pending))
    # Deliver locally, then acknowledge. Real transports acknowledge on success.
    item <- pending[[1]]
    mx_sas_receive(alice, list(sender = "@bob:example.org",
        type = item$type, content = item$content))
    mx_sas_outgoing(bob, acknowledge = item$id)
    stopifnot(length(mx_sas_outgoing(bob)) == 0L)
}
}
