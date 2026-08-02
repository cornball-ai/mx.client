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

mx_table_row_cells <- function(x) {
    x <- trimws(x)
    if (startsWith(x, "|")) {
        x <- substring(x, 2L)
    }
    if (endsWith(x, "|")) {
        x <- substring(x, 1L, nchar(x) - 1L)
    }
    trimws(strsplit(x, "|", fixed = TRUE)[[1]])
}

mx_is_table_separator <- function(x) {
    cells <- mx_table_row_cells(x)
    length(cells) > 0L && all(grepl("^:?-{3,}:?$", cells))
}

mx_is_table_row <- function(x) {
    grepl("\\|", x) && nzchar(trimws(x))
}

mx_table_align <- function(sep) {
    cells <- mx_table_row_cells(sep)
    vapply(cells, function(cell) {
        left <- startsWith(cell, ":")
        right <- endsWith(cell, ":")
        if (left && right) {
            "center"
        } else if (right) {
            "right"
        } else if (left) {
            "left"
        } else {
            NA_character_
        }
    }, character(1))
}

mx_table_html_cells <- function(cells, tag = "td", align = NULL) {
    n <- length(cells)
    if (is.null(align)) {
        align <- rep(NA_character_, n)
    }
    if (length(align) < n) {
        align <- c(align, rep(NA_character_, n - length(align)))
    }
    paste(vapply(seq_len(n), function(i) {
        attr <- if (!is.na(align[[i]]) && nzchar(align[[i]])) {
            sprintf(" align=\"%s\"", align[[i]])
        } else {
            ""
        }
        sprintf("<%s%s>%s</%s>", tag, attr,
                mx_markdown_inline_html(cells[[i]]), tag)
    }, character(1)), collapse = "")
}

mx_table_to_html <- function(rows) {
    header <- mx_table_row_cells(rows[[1]])
    align <- mx_table_align(rows[[2]])
    body <- rows[-c(1L, 2L)]
    html <- c("<table>", "<thead><tr>",
              mx_table_html_cells(header, "th", align),
              "</tr></thead>")
    if (length(body)) {
        body_html <- vapply(body, function(row) {
            cells <- mx_table_row_cells(row)
            # Pad or trim body rows to header width, matching common GFM behavior.
            if (length(cells) < length(header)) {
                cells <- c(cells, rep("", length(header) - length(cells)))
            } else if (length(cells) > length(header)) {
                cells <- cells[seq_along(header)]
            }
            paste0("<tr>", mx_table_html_cells(cells, "td", align), "</tr>")
        }, character(1))
        html <- c(html, "<tbody>", body_html, "</tbody>")
    }
    paste0(c(html, "</table>"), collapse = "")
}

#' Convert a conservative markdown subset to Matrix custom HTML
#'
#' Supports headings, bullets, numbered lists, fenced code blocks, inline
#' code, bold, simple underscore emphasis, and GitHub-style pipe tables.
#'
#' @param text Character markdown body.
#' @return Character HTML suitable for m.room.message formatted_body.
#' @examples
#' mx_markdown_to_html("# Status\n- built\n- checked\n\nShip `0.1.0` **soon**")
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
    i <- 1L
    while (i <= length(lines)) {
        ln <- lines[[i]]
        if (grepl("^```", ln)) {
            if (in_pre) {
                out <- c(out, "</code></pre>")
                in_pre <- FALSE
            } else {
                out <- c(out, close_lists(), "<pre><code>")
                in_pre <- TRUE
            }
            i <- i + 1L
            next
        }
        if (in_pre) {
            out <- c(out, mx_html_escape(ln))
            i <- i + 1L
            next
        }
        if (i < length(lines) && mx_is_table_row(ln) &&
            mx_is_table_separator(lines[[i + 1L]])) {
            j <- i + 2L
            while (j <= length(lines) && mx_is_table_row(lines[[j]])) {
                j <- j + 1L
            }
            out <- c(out, close_lists(), mx_table_to_html(lines[i:(j - 1L)]))
            i <- j
            next
        }
        if (!nzchar(trimws(ln))) {
            out <- c(out, close_lists())
            i <- i + 1L
            next
        }
        h <- regexec("^(#{1,6})\\s+(.+)$", ln, perl = TRUE)
        hm <- regmatches(ln, h)[[1]]
        if (length(hm)) {
            out <- c(out, close_lists())
            lvl <- nchar(hm[[2]])
            body <- hm[[3]]
            out <- c(out, sprintf("<h%d>%s</h%d>", lvl,
                                  mx_markdown_inline_html(body), lvl))
            i <- i + 1L
            next
        }
        b <- regexec("^\\s*[-*]\\s+(.+)$", ln, perl = TRUE)
        bm <- regmatches(ln, b)[[1]]
        if (length(bm)) {
            if (in_ol) {
                out <- c(out, "</ol>")
                in_ol <- FALSE
            }
            if (!in_ul) {
                out <- c(out, "<ul>")
                in_ul <- TRUE
            }
            body <- bm[[2]]
            out <- c(out, sprintf("<li>%s</li>", mx_markdown_inline_html(body)))
            i <- i + 1L
            next
        }
        o <- regexec("^\\s*[0-9]+\\.\\s+(.+)$", ln, perl = TRUE)
        om <- regmatches(ln, o)[[1]]
        if (length(om)) {
            if (in_ul) {
                out <- c(out, "</ul>")
                in_ul <- FALSE
            }
            if (!in_ol) {
                out <- c(out, "<ol>")
                in_ol <- TRUE
            }
            body <- om[[2]]
            out <- c(out, sprintf("<li>%s</li>", mx_markdown_inline_html(body)))
            i <- i + 1L
            next
        }
        out <- c(out, close_lists(), sprintf("<p>%s</p>",
            mx_markdown_inline_html(ln)))
        i <- i + 1L
    }
    if (in_pre) {
        out <- c(out, "</code></pre>")
    }
    out <- c(out, close_lists())
    paste(out, collapse = "")
}

#' Turn textual @mentions into Matrix pills in formatted HTML
#'
#' @param html Character HTML (e.g. from \code{\link{mx_markdown_to_html}}).
#' @param user_ids Character Matrix user ids, such as
#'   \code{"@jorge:example.org"}.
#' @return HTML with textual \code{@localpart} occurrences replaced by
#'   matrix.to links. Unmatched user ids leave the HTML unchanged; they
#'   can still be placed in \code{m.mentions} by \code{mx_send_text()}.
#' @export
mx_pill_mentions <- function(html, user_ids) {
    if (!length(user_ids)) {
        return(html)
    }
    for (uid in unique(user_ids)) {
        local <- sub("^@([^:]+):.*$", "\\1", uid)
        esc <- gsub("([][{}()+*^$.|\\\\?])", "\\\\\\1", local, perl = TRUE)
        pill <- sprintf("<a href=\"https://matrix.to/#/%s\">%s</a>",
                        mx_html_escape(uid), mx_html_escape(local))
        html <- gsub(paste0("@", esc, "(:[A-Za-z0-9._-]+)?\\b"), pill, html,
                     perl = TRUE, ignore.case = TRUE)
    }
    html
}
