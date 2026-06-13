# cran-comments

## Submission

First submission of mx.client to CRAN.

## Test environments

* Ubuntu 24.04, R 4.x (local): R CMD check --as-cran, 0 errors, 0 warnings,
  1 note (new submission)
* win-builder R-devel and R-release (check_win_devel), 2026-06-13

## Notes for the reviewer

* `\dontrun{}` examples are limited to functions that require a live
  Matrix homeserver session or account credentials (login, sync, send,
  room lookup, key upload/claim). Everything that can run locally has a
  runnable or `\donttest{}` example writing only to `tempdir()`.
* The 'mx.crypto' package in Suggests is on CRAN; it is optional because
  it needs a Rust toolchain to build, and all non-encrypted functionality
  works without it.
