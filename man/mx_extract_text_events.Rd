% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_text_events}
\alias{mx_extract_text_events}
\title{Extract text message events from a sync response}
\usage{
mx_extract_text_events(sync_resp, self_id, msgtypes = "m.text")
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}

\item{self_id}{Current user's Matrix id.}

\item{msgtypes}{Character vector of message types to include.}
}
\value{
List of normalized event records.
}
\description{
Walks joined-room timeline events and returns normalized text-message
records. Self events are retained and tagged with \code{is_self}.
}
