% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_key_plan}
\alias{mx_call_key_plan}
\title{Decide what to do with the call key when membership changes}
\usage{
mx_call_key_plan(
  keys,
  identities,
  now = Sys.time(),
  grace = MX_CALL_KEY_GRACE_S
)
}
\arguments{
\item{keys}{Key state from \code{mx_call_keys_new()} (an environment;
it is not modified).}

\item{identities}{LiveKit identities of the other members now in the
call.}

\item{now}{The current time.}

\item{grace}{Seconds after a key is made during which it is still
handed to joiners instead of rotated.}
}
\value{
\code{list(rotate, targets)}: whether to make a new key, and
  the identities to send the (new or current) key to.
}
\description{
Implements the rotation policy Element Call and FluffyChat follow: a
leaver forces a new key for everyone; a joiner within the grace period
after the key was made receives the current key; a joiner after it
gets a new key, as does everyone else.
}
\examples{
keys <- mx.client:::mx_call_keys_new()
mx_call_key_plan(keys, c("@a:ex:D1", "@b:ex:D2"))
}
