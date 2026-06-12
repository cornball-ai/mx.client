% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_markdown_to_html}
\alias{mx_markdown_to_html}
\title{Convert a conservative markdown subset to Matrix custom HTML}
\usage{
mx_markdown_to_html(text)
}
\arguments{
\item{text}{Character markdown body.}
}
\value{
Character HTML suitable for m.room.message formatted_body.
}
\description{
Supports headings, bullets, numbered lists, fenced code blocks, inline
code, bold, and simple underscore emphasis.
}
\examples{
mx_markdown_to_html("# Status\n- built\n- checked\n\nShip `0.1.0` **soon**")
}
