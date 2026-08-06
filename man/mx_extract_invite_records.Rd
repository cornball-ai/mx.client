% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_extract_invite_records}
\alias{mx_extract_invite_records}
\title{Extract pending invites with the member who sent them}
\usage{
mx_extract_invite_records(sync_resp, self_id = NULL)
}
\arguments{
\item{sync_resp}{Parsed \code{/sync} response.}

\item{self_id}{Current user's Matrix id, whose membership event names
the inviter. NULL reports every invite with \code{inviter} NA.}
}
\value{
List of records, each \code{list(room_id, inviter)}.
}
\description{
The fuller form of \code{\link{mx_extract_invites}}, which reports
only room ids. An invite's sender is the whole of whether it should be
accepted -- auto-joining anyone's invite hands a stranger a session
with whatever the client can do -- and a caller that wants to decide
had to walk \code{invite_state} itself to find out.
}
\details{
The sender comes from the stripped state the homeserver sends
alongside an invite: the \code{m.room.member} event whose
\code{state_key} is \code{self_id} and whose membership is
\code{"invite"}. That is not always present, so \code{inviter} is NA
when it is missing rather than guessed at, and a caller gating on it
can tell "nobody I trust" from "I could not tell".

Stripped state carries no reliable \code{origin_server_ts}, so there
is no timestamp here. An invite is a standing state, not an event at a
moment.

}
\examples{
sync_resp <- list(rooms = list(invite = list(`!inv:example.org` = list(
    invite_state = list(events = list(list(type = "m.room.member",
        state_key = "@bot:example.org", sender = "@ann:example.org",
        content = list(membership = "invite"))))))))
mx_extract_invite_records(sync_resp, self_id = "@bot:example.org")
}
