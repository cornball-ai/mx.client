% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_record_trust}
\alias{mx_sas_record_trust}
\title{Record trust after a human-confirmed, authenticated SAS exchange}
\usage{
mx_sas_record_trust(sas, client, store_dir, now = Sys.time())
}
\arguments{
\item{sas}{A SAS transaction with both human confirmation and valid peer MACs.}

\item{client}{This device's Matrix client config.}

\item{store_dir}{This device's existing cross-signing store.}

\item{now}{Current time.}
}
\value{
The transaction, invisibly. Errors leave completion retryable.
}
\description{
Rechecks the fixed identity snapshot, signs the peer master with this
user's user-signing key (or its own peer device with its self-signing key),
and verifies server read-back. Only then is done queued. A peer's done
acknowledgement does not expose or prove its private user-signing key.
}
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    example("mx_sas_session", package = "mx.client", echo = FALSE)
    client <- mx_client_from_config(list(user_id = "@alice:example.org",
        device_id = "ALICE"))
    unused_store <- tempfile("unused-crypto-store-")
    # An unconfirmed exchange cannot grant trust or access the crypto store.
    try(mx_sas_record_trust(alice, client, unused_store))
    stopifnot(!mx_sas_status(alice)$local_trust_recorded,
        !file.exists(unused_store))
}
# mx_verify_console() calls this after human confirmation and valid peer MACs.
}
