% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_pill_mentions}
\alias{mx_pill_mentions}
\title{Turn textual @mentions into matrix.to pills}
\usage{
mx_pill_mentions(html, user_ids)
}
\arguments{
\item{html}{Character HTML (e.g. from \code{\link{mx_markdown_to_html}}).}

\item{user_ids}{Character vector of full Matrix user ids.}
}
\value{
Character HTML with mention pills.
}
\description{
Replaces each occurrence of \code{@localpart} (or the full
\code{@localpart:server} id) in already-rendered HTML with a
\code{matrix.to} anchor, which Matrix clients render as a mention pill.
A user id with no textual occurrence is left to \code{m.mentions} alone,
which still notifies.
}
