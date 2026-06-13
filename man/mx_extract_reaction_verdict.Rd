% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_reaction_verdict}
\alias{mx_extract_reaction_verdict}
\title{Extract a reaction approval verdict from sync events}
\usage{
mx_extract_reaction_verdict(sync_resp, room_id, self_id, target_event_id,
                            approve_keys = NULL, deny_keys = NULL)
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}

\item{room_id}{Character room id.}

\item{self_id}{Current user's Matrix id.}

\item{target_event_id}{Event id being reacted to.}

\item{approve_keys}{Character vector of reaction keys read as approval.
\code{NULL} (default) uses thumbs-up (U+1F44D), check-mark (U+2705),
and \code{"y"}/\code{"yes"}/\code{"ok"}.}

\item{deny_keys}{Character vector of reaction keys read as denial.
\code{NULL} (default) uses thumbs-down (U+1F44E), cross-mark
(U+274C), and \code{"n"}/\code{"no"}/\code{"nope"}.}
}
\value{
TRUE, FALSE, or NULL.
}
\description{
Scans a room timeline for a reaction on \code{target_event_id} from
someone other than \code{self_id}. Returns TRUE for approval keys,
FALSE for denial keys, or NULL when no verdict is present.
}
\examples{
sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
    timeline = list(events = list(list(type = "m.reaction",
        sender = "@alice:example.org",
        content = list("m.relates_to" = list(rel_type = "m.annotation",
            event_id = "$msg", key = "yes")))))))))
mx_extract_reaction_verdict(sync_resp, "!room:example.org",
                            self_id = "@bot:example.org",
                            target_event_id = "$msg")
}
