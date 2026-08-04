# cran-comments

## Submission

Minor release, 0.1.1 -> 0.2.0.

The headline is a set of security fixes to the optional end-to-end
encryption path. mx.client built and consumed Matrix E2EE payloads
without verifying anything the homeserver returned:

* `/keys/query` device keys were read straight out of the response with
  their Ed25519 self-signature ignored, so a malicious or compromised
  homeserver could substitute its own Curve25519 key for any device and
  read everything sent to that user.
* `/keys/claim` one-time keys were taken with their signatures
  discarded.
* Outbound Olm payloads omitted the `sender` / `recipient` /
  `recipient_keys` / `keys` block the Matrix spec requires, leaving
  receivers nothing to authenticate against.
* Inbound Olm payloads were acted on without checking they named this
  device as recipient.

All four are fixed, using the verification helpers `mx.crypto` 0.2.0
added for this purpose. `Suggests` is now `mx.crypto (>= 0.2.0)`.

The release also adds Matrix table rendering (`mx_table_html()`,
`mx_send_table()`, and pipe-table support in `mx_markdown_to_html()`),
`mx_set_displayname()`, and a `print()` method for `mx_client_config`
that masks credentials.

## Breaking changes

`mx_crypto_room_key_payload()` takes four further arguments
(`sender_user_id`, `sender_ed25519`, `recipient_user_id`,
`recipient_ed25519`). They are what the payload's authentication block
is built from, so they deliberately have no defaults: a five-argument
call now errors rather than silently emitting a payload no receiver can
authenticate. `mx_crypto_encrypt_for_devices()` and
`mx_crypto_handle_to_device()` gain arguments in the same vein.

This is why the version takes a minor bump rather than a patch. There
are no reverse dependencies on CRAN.

## Test environments

* Ubuntu 24.04, R 4.5.3 (local): `R CMD check --as-cran`, 0 errors,
  0 warnings, 0 notes
* Windows 10, R 4.6.0: `R CMD check --as-cran`, Status OK
* Windows 10, R-devel (2026-07-21 r90286 ucrt): `R CMD check --as-cran`,
  Status OK
* GitHub Actions (ubuntu-latest, macos-latest) via r-ci, R-release
* win-builder R-devel and R-release

## Notes for the reviewer

* `\dontrun{}` examples are limited to functions needing a live Matrix
  homeserver session or account credentials (login, sync, send, room
  lookup, key upload/claim). Everything runnable locally has a runnable
  or `\donttest{}` example writing only to `tempdir()`.
* `mx.crypto` in Suggests is on CRAN. It is optional because it needs a
  Rust toolchain to build, and every non-encrypted code path works
  without it. The Windows checks above ran with
  `_R_CHECK_FORCE_SUGGESTS_=false` for that reason.
