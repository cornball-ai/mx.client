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
\examples{
# Ordinary messages are ignored without reading a store or contacting a server.
client <- mx_client_from_config(list(user_id = "@alice:example.org",
    device_id = "ALICE"))
event <- list(type = "m.room.message", sender = "@bob:example.org",
    content = list(msgtype = "m.text", body = "Hello"))
unused_store <- tempfile("unused-crypto-store-")
stopifnot(is.null(mx_sas_from_request(client, unused_store, event)),
    !file.exists(unused_store))
# See mx_verify_console() for receiving real requests using an existing store.
}
