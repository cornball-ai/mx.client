library(tinytest)

root <- system.file("skills", package = "mx.client")
expect_true(nzchar(root))
skill <- file.path(root, "matrix-messaging", "SKILL.md")
expect_true(file.exists(skill))
expect_false(file.exists(file.path(root, "mx.client",
                                  "matrix-messaging", "SKILL.md")))
entries <- list.files(root, pattern = "^SKILL[.]md$", recursive = TRUE)
expect_equal(entries, "matrix-messaging/SKILL.md")
body <- readLines(skill, warn = FALSE)
expect_equal(body[[1L]], "---")
expect_true("name: matrix-messaging" %in% body)
expect_true(any(grepl("^description:", body)))
