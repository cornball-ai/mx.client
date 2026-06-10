% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_publish_keys}
\alias{mx_crypto_publish_keys}
\title{Publish this device's identity and one-time keys}
\usage{
mx_crypto_publish_keys(client, account, store_dir, n_otks = 50L)
}
\arguments{
\item{client}{Matrix client config (needs \code{user_id},
\code{device_id}).}

\item{account}{An mx.crypto account handle.}

\item{store_dir}{Character. Crypto store directory.}

\item{n_otks}{Integer. Number of one-time keys to publish.}
}
\value{
The \code{/keys/upload} response, invisibly.
}
\description{
Builds and signs the device keys and a batch of one-time keys, uploads
them with \code{mx.api::mx_keys_upload()}, marks them published, and
persists the account. Call once after login and again to replenish
one-time keys.
}
\examples{
\dontrun{
acct <- mx_crypto_account(mx_crypto_store_dir("corteza"))
mx_crypto_publish_keys(mx_client_load(app = "corteza"), acct,
                       mx_crypto_store_dir("corteza"))
}
}
