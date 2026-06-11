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
