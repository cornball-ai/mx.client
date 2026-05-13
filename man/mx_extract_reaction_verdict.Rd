% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_reaction_verdict}
\alias{mx_extract_reaction_verdict}
\title{Extract a reaction approval verdict from sync events}
\usage{
mx_extract_reaction_verdict(sync_resp, room_id, self_id, target_event_id,
                            approve_keys = c("👍", "✅", "y", "yes", "ok"),
                            deny_keys = c("👎", "❌", "n", "no", "nope"))
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}

\item{room_id}{Character room id.}

\item{self_id}{Current user's Matrix id.}

\item{target_event_id}{Event id being reacted to.}

\item{approve_keys}{Character vector.}

\item{deny_keys}{Character vector.}
}
\value{
TRUE, FALSE, or NULL.
}
\description{
Scans a room timeline for a reaction on \code{target_event_id} from
someone other than \code{self_id}. Returns TRUE for approval keys,
FALSE for denial keys, or NULL when no verdict is present.
}
