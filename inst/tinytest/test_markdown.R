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
