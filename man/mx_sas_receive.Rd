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
