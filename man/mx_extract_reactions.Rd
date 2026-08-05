% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_reactions}
\alias{mx_extract_reactions}
\title{Extract reaction events from a sync response}
\usage{
mx_extract_reactions(sync_resp, self_id)
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}

\item{self_id}{Current user's Matrix id.}
}
\value{
List of records, each carrying \code{room_id},
  \code{event_id} (the reaction's own id, not its target),
  \code{sender}, \code{is_self}, \code{target_event_id} (the annotated
  event), \code{key} (the reaction text, usually an emoji), and
  \code{ts} (\code{origin_server_ts} in milliseconds, or NULL when the
  server omits it). An \code{m.reaction} carrying no annotation
  relation, no target, or no key is not a reaction to anything and is
  skipped.
}
\description{
Walks joined-room timelines and returns every \code{m.reaction} that
annotates another event. Self reactions are retained and tagged with
\code{is_self}, the same way \code{\link{mx_extract_text_events}}
treats the client's own messages: a consumer that wants only other
people's reactions filters on the flag, and one tracking its own
(which reactions it has already placed) needs them.
}
\details{
This is the general form of \code{\link{mx_extract_reaction_verdict}},
which answers one approve/deny question about one event. That function
bakes in which keys mean yes and which mean no, and stays for callers
who want that; this one reports keys and leaves their meaning alone.

Only additions are reported. Removing a reaction is an
\code{m.room.redaction} of the \code{m.reaction} event, which is not an
\code{m.reaction} and so does not appear here -- a consumer that has to
notice un-reactions needs to read redactions itself.

}
\examples{
sync_resp <- list(rooms = list(join = list("!room:example.org" = list(
    timeline = list(events = list(list(type = "m.reaction",
        event_id = "$r1", sender = "@alice:example.org",
        content = list("m.relates_to" = list(rel_type = "m.annotation",
            event_id = "$msg", key = "+1")))))))))
mx_extract_reactions(sync_resp, self_id = "@bot:example.org")
}
