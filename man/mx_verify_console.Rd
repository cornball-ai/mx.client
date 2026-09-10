% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_verify_console}
\alias{mx_verify_console}
\title{Verify a Matrix client interactively from an R console}
\usage{
mx_verify_console(
  client,
  store_dir,
  peer_user_id,
  room_id = NULL,
  exclusive = FALSE,
  timeout = 120,
  on_messages = verification_print_messages
)
}
\arguments{
\item{client}{Client loaded with mx_client_load() from its existing config.}

\item{store_dir}{This device's existing, initialized crypto store.}

\item{peer_user_id}{Full Matrix id of the person being verified.}

\item{room_id}{Exact room id, or NULL for to-device requests.}

\item{exclusive}{Must explicitly be TRUE after stopping other consumers
of this device and store. FALSE refuses before any network or store access.}

\item{timeout}{Maximum seconds to wait for an initial request, 1 to 600.}

\item{on_messages}{Function receiving ordinary messages read while the
console owns sync. The default reports only their count, keeping untrusted
chat text out of the verification prompts; content is returned in messages.}
}
\value{
Invisibly, a list with status, updated client, and ordinary messages.
}
\description{
Owns the device's existing sync cursor and crypto store while waiting for
a verification request from the selected user and room. In the other
client, choose Start verification, then compare the emoji or numbers in
its UI with this trusted console. No private client database, desktop
keyring, or remote user's private signing key is read.
}
\details{
Stop any bot or other process using this device before calling. The
exclusive argument is an explicit operator assertion, not a process lock.
Restart that process only after this call returns. Ordinary messages read
during this session go to on_messages and are returned for review; a bot
will not automatically process messages whose cursor the console advanced.
Existing event-loop hosts can instead use mx_sas_from_request() and
mx_sas_console() with their own receive/send callbacks.
Each attempt reloads the saved cursor and credentials, refusing a changed
server, user, or device identity rather than replaying the caller's old cursor.

}
\examples{
\dontrun{
# First stop the service using this exact device and crypto store.
client <- mx_client_load(path = config_path)
result <- mx_verify_console(client, existing_store,
    "@peer:example.org", "!room:example.org", exclusive = TRUE)
# In the peer's Matrix app, choose Start verification.
# Restart the service after the console returns.
}
}
