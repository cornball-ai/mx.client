% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_send_to_device_encrypted}
\alias{mx_send_to_device_encrypted}
\title{Send an Olm-encrypted to-device event}
\usage{
mx_send_to_device_encrypted(
  client,
  account,
  sessions,
  event_type,
  content,
  devices,
  store_dir = NULL
)
}
\arguments{
\item{client}{Matrix client config.}

\item{account}{An mx.crypto account handle.}

\item{sessions}{A session set.}

\item{event_type}{The inner event type.}

\item{content}{Named list. Plaintext event content.}

\item{devices}{List of target devices from
\code{mx_crypto_known_devices()}, already narrowed to the devices
that should receive the event.}

\item{store_dir}{Character or NULL. Where to persist the updated
sessions; NULL leaves saving to the caller.}
}
\value{
List with \code{sessions} (updated) and \code{sent}, the
  \code{list(user_id, device_id)} pairs the event went to.
}
\description{
Encrypts \code{content} for each device in \code{devices}, claiming
one-time keys where no Olm session exists, and delivers it with
\code{mx.api::mx_send_to_device()} in one request. This device itself
is never a recipient.
}
\examples{
\dontrun{
devs <- mx_crypto_known_devices(client, "@bob:example.org")
mx_send_to_device_encrypted(client, acct, sessions, "org.example.ping",
                            list(n = 1), devs, store_dir)
}
}
