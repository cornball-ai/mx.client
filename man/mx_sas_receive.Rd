% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_receive}
\alias{mx_sas_receive}
\title{Receive one standard Matrix SAS protocol event}
\usage{
mx_sas_receive(sas, event = NULL, now = Sys.time())
}
\arguments{
\item{sas}{An in-memory SAS transaction.}

\item{event}{A Matrix event envelope with type, sender, content, and
room_id for in-room verification, or NULL.}

\item{now}{Current time.}
}
\value{
The transaction, invisibly.
}
\description{
Ignores other senders, rooms, devices, and transaction ids. Invalid
messages in this transaction cancel it. Duplicate identical messages do
not repeat operations; conflicting repeats cancel. NULL checks timeouts.
Feed decrypted original event type and content, not flattened chat text.
No transport or persistent trust operation occurs here.
}
\examples{
if (requireNamespace("mx.crypto", quietly = TRUE)) {
    example("mx_sas_session", package = "mx.client", echo = FALSE)
    # Deliver queued envelopes between the two synthetic, in-memory peers.
    relay <- function(from, to) {
        for (item in mx_sas_outgoing(from)) {
            mx_sas_receive(to, list(type = item$type, content = item$content,
                sender = mx_sas_status(from)$user_id, room_id = item$room_id))
            mx_sas_outgoing(from, acknowledge = item$id)
        }
    }
    mx_sas_accept(bob)
    for (i in seq_len(3)) {
        relay(bob, alice)
        relay(alice, bob)
    }
    alice_status <- mx_sas_status(alice)
    bob_status <- mx_sas_status(bob)
    stopifnot(identical(alice_status$phase, "sas"),
        identical(bob_status$phase, "sas"),
        length(alice_status$decimal) == 3L,
        identical(alice_status$decimal, bob_status$decimal),
        !alice_status$confirmed, !alice_status$local_trust_recorded)
    # A real exchange still requires a human comparison on trusted displays.
}
}
