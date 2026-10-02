% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_call_connect}
\alias{mx_call_connect}
\title{Join the LiveKit room of a call}
\usage{
mx_call_connect(call, ...)
}
\arguments{
\item{call}{An \code{"mx_call"}.}

\item{...}{Further arguments to \code{livekitr::lk_connect()}, such
as \code{opts}.}
}
\value{
\code{call}, invisibly.
}
\description{
Connects the media side of a call made with \code{mx_call_join(connect
= FALSE)}: joins the LiveKit room with the media token, with
end-to-end encryption configured as Element Call and FluffyChat
expect (per-participant HKDF keys, a 256-slot key ring), and sets our
key and every peer key received so far.
}
