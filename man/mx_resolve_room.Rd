% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_resolve_room}
\alias{mx_resolve_room}
\title{Resolve a room id, name, or default room}
\usage{
mx_resolve_room(client, room = NULL, room_cache = NULL, fallback = TRUE,
                details = FALSE, quiet = FALSE)
}
\arguments{
\item{client}{Matrix client config.}

\item{room}{Character or NULL.}

\item{room_cache}{Named list or character vector mapping names to ids.}

\item{fallback}{Logical. Use \code{client$room_id} when lookup misses.}

\item{details}{Logical. Return source metadata instead of just the id.}

\item{quiet}{Logical. Suppress fallback message.}
}
\value{
Character room id, or a list when \code{details = TRUE}.
}
\description{
Resolution order:
literal room IDs beginning with \code{!}, a supplied \code{room_cache}
name-to-id map, joined-room display-name lookup, then the config's
\code{room_id} fallback.
}
