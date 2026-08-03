% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_table_html}
\alias{mx_table_html}
\title{Render tabular data as Matrix custom HTML}
\usage{
mx_table_html(x, header = TRUE)
}
\arguments{
\item{x}{A data frame, matrix, or list coercible to a data frame.}

\item{header}{Logical. Include a header row using column names.}
}
\value{
Character HTML suitable for Matrix \code{formatted_body}.
}
\description{
Produces the conservative table shape rendered by Matrix clients such as
FluffyChat 2.6.0+: a bare \code{<table>} containing \code{<tr>},
\code{<th>}, and \code{<td>} nodes. No CSS, colspan, rowspan, or custom
attributes are emitted.
}
\examples{
mx_table_html(data.frame(A = 1:2, B = c("x", "y")))
}
