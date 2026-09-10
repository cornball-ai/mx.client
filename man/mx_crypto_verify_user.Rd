% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_verify_user}
\alias{mx_crypto_verify_user}
\title{Verify another Matrix user's independently authenticated identity}
\usage{
mx_crypto_verify_user(client, store_dir, user_id, master_key)
}
\arguments{
\item{client}{Matrix client config for the account granting trust.}

\item{store_dir}{Character. That account's existing cross-signing store.}

\item{user_id}{Character. The other user's full Matrix id.}

\item{master_key}{Character. The other user's full master public key,
authenticated independently of the homeserver being queried.}
}
\value{
The same status list as \code{mx_crypto_user_trust()}, with verified
  TRUE, invisibly. An error is raised if read-back does not confirm trust.
}
\description{
Signs the other user's pinned master key with this account's existing
user-signing key. Uploads only a missing or invalid signature, then queries
it back and verifies it before reporting success. No private keys are sent.
A successful upload followed by a failed read-back may already have recorded
trust; rerunning with the same authenticated key is safe.
}
\details{
This establishes one direction only. For mutual verification, preflight
both accounts with \code{mx_crypto_user_trust()}, then call this function
once as each account using the other account's independently checked pin.
The two uploads are not atomic. No SAS handshake or history-key sharing is
performed, and devices still need their own valid self-signing chains.

}
\examples{
\dontrun{
mx_crypto_verify_user(client, existing_store, "@peer:example.org", peer_pin)
}
}
