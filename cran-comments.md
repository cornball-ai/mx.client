# cran-comments

## Submission

Update from CRAN version 0.2.1 to 0.3.0.

This release adds encrypted attachment upload and verified download
(`mx_upload_encrypted()`, `mx_download_encrypted()`) and Olm-encrypted
to-device events of any type (`mx_send_to_device_encrypted()`,
`mx_crypto_encrypt_to_device()`). It fixes the loss of inbound Olm
messages sent on a session the peer had opened earlier, and
`mx_set_displayname()` now returns the client it used so a caller can
keep a refreshed token.

The mandatory mx.api floor is unchanged at 0.3.0.2. The optional
mx.crypto floor rises to 0.3.0, now on CRAN, for the attachment
primitives. All dependencies are on CRAN. Unencrypted client operations
still work without mx.crypto.

## API and compatibility

No exports were removed or renamed. `mx_send_encrypted()` gains an
optional `event_type` argument. `mx_crypto_process_sync()` adds a
`to_device` element to its result and keeps each decrypted room event's
`type` and `content`.

`mx_set_displayname()` returned `TRUE` invisibly and now returns the
client config invisibly. Neither reverse dependency uses the value.

`mx_send_media()` now refuses a plaintext upload to an encrypted room.

Session stores written by 0.2.1 load unchanged: a single inbound Olm
session per peer becomes a one-element list.

## Test environments

All local checks used a library built from CRAN source packages only.

* Ubuntu 24.04.5, R 4.6.1: R CMD check --as-cran --run-donttest,
  including PDF and HTML manuals, examples, tests, and rebuilt vignettes,
  with mx.crypto 0.3.0 installed. Status: OK.
* The same check with mx.crypto absent. Status: OK.
* Installed test suite with an empty HOME: 873 assertions passed and no
  file was written under HOME.
* R-oldrelease was not checked for this release.

## Reverse dependencies

chat.api 0.1.0 and corteza 0.7.1, both reverse Suggests from CRAN, were
checked against the 0.3.0 tarball. Both: Status: OK.

## Examples

The encrypted-media examples are in \dontrun because they need account
credentials and a live Matrix homeserver. All executed example and test
writes use temporary directories.
