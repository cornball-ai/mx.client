library(tinytest)

html <- mx.client::mx_markdown_to_html(paste(c(
    "# Heading",
    "",
    "- one `code`",
    "- **two**",
    "",
    "```",
    "x < y & z",
    "```"
), collapse = "\n"))

expect_true(grepl("<h1>Heading</h1>", html, fixed = TRUE))
expect_true(grepl("<ul><li>one <code>code</code></li><li><strong>two</strong></li></ul>", html, fixed = TRUE))
expect_true(grepl("x &lt; y &amp; z", html, fixed = TRUE))

# mention pills
p <- mx.client::mx_pill_mentions("hey @Jorge, ping @jorge:cornball.ai too",
                                 "@jorge:cornball.ai")
pill <- "<a href=\"https://matrix.to/#/@jorge:cornball.ai\">jorge</a>"
expect_equal(p, paste0("hey ", pill, ", ping ", pill, " too"))

# localpart with a dot doesn't go regex-wild; unmentioned text untouched
p2 <- mx.client::mx_pill_mentions("@j.r rules, @jXr does not",
                                  "@j.r:cornball.ai")
expect_true(grepl("matrix.to/#/@j.r:cornball.ai", p2, fixed = TRUE))
expect_true(grepl("@jXr does not", p2, fixed = TRUE))

# no textual occurrence: html unchanged (m.mentions still notifies)
expect_equal(mx.client::mx_pill_mentions("no names here", "@tiny:cornball.ai"),
             "no names here")

# GitHub-style pipe tables become Matrix custom HTML tables.
tab <- mx.client::mx_markdown_to_html(paste(c(
    "| Area | OKF | pensar |",
    "|---|---|---|",
    "| Links | Markdown links | `[[wikilinks]]` |",
    "| Strictness | only **type** | title, type, source |"
), collapse = "\n"))
expect_true(grepl("<table>", tab, fixed = TRUE))
expect_true(grepl("<th>Area</th>", tab, fixed = TRUE))
expect_true(grepl("<td><code>[[wikilinks]]</code></td>", tab, fixed = TRUE))
expect_true(grepl("<strong>type</strong>", tab, fixed = TRUE))

# Known-good Matrix room shape from the Cornelius CRAN downloads report.
# This pins the exact format that rendered in-client: blank line before the
# pipe table, backticked package names, right-aligned numeric/date columns,
# and ordinary prose after the table.
known_good <- mx.client::mx_markdown_to_html(paste(c(
    "**CRAN downloads weekly** (16 packages, as of 2026-07-20)",
    "",
    "| package | last week | last month | total |",
    "|---|---:|---:|---:|",
    "| `tinyoauth` | 63 | 543 | 601 |",
    "| `saber` | 51 | 443 | 2,395 |",
    "",
    "* Partial period: package has not been on CRAN for the full week or month."
), collapse = "\n"))
expect_true(grepl("<table>", known_good, fixed = TRUE))
expect_true(grepl("<p><strong>CRAN downloads weekly</strong>", known_good,
                  fixed = TRUE))
expect_true(grepl("<td><code>tinyoauth</code></td>", known_good, fixed = TRUE))
expect_true(grepl("<td align=\"right\">2,395</td>", known_good, fixed = TRUE))
expect_true(grepl("Partial period", known_good, fixed = TRUE))
