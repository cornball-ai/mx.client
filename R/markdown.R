# Conservative markdown-to-Matrix-HTML formatting.

mx_html_escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    x
}

mx_markdown_inline_html <- function(x) {
    x <- mx_html_escape(x)
    x <- gsub("`([^`]+)`", "<code>\\1</code>", x, perl = TRUE)
    x <- gsub("\\*\\*([^*]+)\\*\\*", "<strong>\\1</strong>", x, perl = TRUE)
    x <- gsub("\\b_([^_]+)_\\b", "<em>\\1</em>", x, perl = TRUE)
    x
}

#' Convert a conservative markdown subset to Matrix custom HTML
#'
#' Supports headings, bullets, numbered lists, fenced code blocks, inline
#' code, bold, and simple underscore emphasis.
#'
#' @param text Character markdown body.
#' @return Character HTML suitable for m.room.message formatted_body.
#' @export
mx_markdown_to_html <- function(text) {
    lines <- strsplit(text %||% "", "\n", fixed = TRUE)[[1]]
    out <- character()
    in_pre <- FALSE
    in_ul <- FALSE
    in_ol <- FALSE
    close_lists <- function() {
        z <- character()
        if (in_ul) {
            z <- c(z, "</ul>")
            in_ul <<- FALSE
        }
        if (in_ol) {
            z <- c(z, "</ol>")
            in_ol <<- FALSE
        }
        z
    }
    for (ln in lines) {
        if (grepl("^```", ln)) {
            if (in_pre) {
                out <- c(out, "</code></pre>")
                in_pre <- FALSE
            } else {
                out <- c(out, close_lists(), "<pre><code>")
                in_pre <- TRUE
            }
            next
        }
        if (in_pre) {
            out <- c(out, mx_html_escape(ln))
            next
        }
        if (!nzchar(trimws(ln))) {
            out <- c(out, close_lists())
            next
        }
        if (grepl("^#{1,6}\\s+", ln)) {
            out <- c(out, close_lists())
            lvl <- nchar(sub("^(#{1,6}).*$", "\\1", ln))
            body <- sub("^#{1,6}\\s+", "", ln)
            out <- c(out, sprintf("<h%d>%s</h%d>", lvl,
                                  mx_markdown_inline_html(body), lvl))
            next
        }
        if (grepl("^\\s*[-*]\\s+", ln)) {
            if (!in_ul) {
                out <- c(out, close_lists(), "<ul>")
                in_ul <- TRUE
            }
            body <- sub("^\\s*[-*]\\s+", "", ln)
            out <- c(out, sprintf("<li>%s</li>", mx_markdown_inline_html(body)))
            next
        }
        if (grepl("^\\s*[0-9]+[.)]\\s+", ln)) {
            if (!in_ol) {
                out <- c(out, close_lists(), "<ol>")
                in_ol <- TRUE
            }
            body <- sub("^\\s*[0-9]+[.)]\\s+", "", ln)
            out <- c(out, sprintf("<li>%s</li>", mx_markdown_inline_html(body)))
            next
        }
        out <- c(out, close_lists(), sprintf("<p>%s</p>",
                                             mx_markdown_inline_html(ln)))
    }
    out <- c(out, close_lists())
    if (in_pre) {
        out <- c(out, "</code></pre>")
    }
    paste(out, collapse = "")
}
