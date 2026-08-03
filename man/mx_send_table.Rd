% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_send_table}
\alias{mx_send_table}
\title{Send tabular data to a Matrix room}
\usage{
mx_send_table(client, x, room = NULL, header = TRUE, title = NULL,
              room_cache = NULL, dry_run = FALSE)
}
\arguments{
\item{client}{Matrix client config.}

\item{x}{A data frame, matrix, or list coercible to a data frame.}

\item{room}{Character room id/name or NULL for the default room.}

\item{header}{Logical. Include a header row using column names.}

\item{title}{Optional text prepended to the plain fallback body.}

\item{room_cache}{Optional room name-to-id cache.}

\item{dry_run}{Logical. Print instead of sending.}
}
\value{
Event id, or NULL on dry-run.
}
\description{
Sends a plain-text fallback body plus Matrix custom HTML table in
\code{formatted_body}. This bypasses Markdown entirely.
}
\examples{
client <- list(room_id = "!default:example.org")
mx_send_table(client, data.frame(A = 1, B = 2), dry_run = TRUE)
}
