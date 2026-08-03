library(tinytest)

html <- mx.client::mx_table_html(data.frame(A = c("1", "<x>"), B = c("&", "two")))
expect_equal(html, paste0(
    "<table>",
    "<tr><th>A</th><th>B</th></tr>",
    "<tr><td>1</td><td>&amp;</td></tr>",
    "<tr><td>&lt;x&gt;</td><td>two</td></tr>",
    "</table>"))

expect_null(mx.client::mx_send_table(list(room_id = "!default:example.org"),
                                     data.frame(A = 1, B = 2),
                                     dry_run = TRUE))

# header = FALSE has to drop the header from both renderings, or the
# plain-text fallback shows a different table than formatted_body does.
d <- data.frame(A = c("1", "2"), B = c("x", "y"))
expect_equal(mx.client:::mx_table_plain(d, header = TRUE), "A | B\n1 | x\n2 | y")
expect_equal(mx.client:::mx_table_plain(d, header = FALSE), "1 | x\n2 | y")
expect_false(grepl("<th>", mx.client::mx_table_html(d, header = FALSE)))
