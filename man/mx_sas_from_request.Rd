% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_from_request}
\alias{mx_sas_from_request}
\title{Create a SAS transaction from an incoming verification request}
\usage{
mx_sas_from_request(client, store_dir, event, now = Sys.time())
}
\arguments{
\item{client}{This device's Matrix client config.}

\item{store_dir}{This device's existing crypto store.}

\item{event}{Original request envelope from the existing event consumer.}

\item{now}{Current time.}
}
\value{
An in-memory SAS transaction, or NULL for an irrelevant/expired request.
}
\description{
Validates the request's age, recipient, device and method, then reads a
fixed key snapshot. No sync, transport, new identity, or trust upload occurs.
Requests are accepted only when the operator calls mx_sas_accept().
}
