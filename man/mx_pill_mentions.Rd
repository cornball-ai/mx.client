% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_pill_mentions}
\alias{mx_pill_mentions}
\title{Turn textual @mentions into Matrix pills in formatted HTML}
\usage{
mx_pill_mentions(html, user_ids)
}
\arguments{
\item{html}{Character HTML (e.g. from \code{\link{mx_markdown_to_html}}).}

\item{user_ids}{Character Matrix user ids, such as
\code{"@jorge:example.org"}.}
}
\value{
HTML with textual \code{@localpart} occurrences replaced by
  matrix.to links. Unmatched user ids leave the HTML unchanged; they
  can still be placed in \code{m.mentions} by \code{mx_send_text()}.
}
\description{
Turn textual @mentions into Matrix pills in formatted HTML
}
\examples{
mx_pill_mentions("<p>ping @jorge</p>", "@jorge:example.org")
}
