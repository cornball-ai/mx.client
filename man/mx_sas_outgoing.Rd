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
