% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_crypto_user_trust}
\alias{mx_crypto_user_trust}
\title{Check a directional Matrix identity verification}
\usage{
mx_crypto_user_trust(client, store_dir, user_id, master_key)
}
\arguments{
\item{client}{Matrix client config for the account whose trust is checked.}

\item{store_dir}{Character. That account's existing cross-signing store.}

\item{user_id}{Character. The other user's full Matrix id.}

\item{master_key}{Character. The other user's full, unpadded base64 master
public key, authenticated through a trusted independent channel. Do not
obtain this pin solely from the homeserver response being checked.}
}
\value{
A list with user_id, master_key, signer_user_id, signer_master_key,
  and verified. FALSE means the expected identities were found but the
  directional trust signature was absent or invalid. Key mismatches error.
}
\description{
Reads the homeserver's signature on another user's master key and verifies
it through this user's locally pinned master and user-signing keys. Both
identities must match their expected keys. This does not upload signatures,
initialize a store, run sync, or modify encryption sessions.
}
\examples{
\dontrun{
mx_crypto_user_trust(client, existing_store, "@peer:example.org", peer_pin)
}
}
