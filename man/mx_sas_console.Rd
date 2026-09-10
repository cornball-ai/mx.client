% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_sas_console}
\alias{mx_sas_console}
\title{Compare a Matrix SAS through a trusted interactive console}
\usage{
mx_sas_console(sas, receive, send, complete, input = sas_console_read)
}
\arguments{
\item{sas}{An in-memory transaction from mx_sas_from_request().}

\item{receive}{Function with no arguments returning a list of original
Matrix events from the sole event consumer. It should wait briefly.}

\item{send}{Function accepting one outgoing envelope. It must throw on
failure and use the envelope's id for idempotent retries.}

\item{complete}{Function accepting sas, recording and checking durable trust
with mx_sas_record_trust(), outside the crypto commit window.}

\item{input}{Function taking a prompt. The default requires an interactive
console; replacement is intended for a trusted human UI or isolated tests.}
}
\value{
A status list, invisibly. Interrupts cancel and attempt notification.
}
\description{
Drives one transaction using the application's existing event consumer.
No second sync loop is created by this function. The human must explicitly
type yes after comparing all seven emoji or all three numbers with the peer.
Empty input, no, or cancellation grants no trust. Do not connect the input
callback to an LLM or a Matrix room.
}
