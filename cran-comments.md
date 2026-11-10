# cran-comments

## Submission

Update from CRAN version 0.2.1 to 0.3.0.

This release adds MatrixRTC calls over LiveKit (`mx_call_join()` and
related functions), encrypted attachment upload and verified download
(`mx_upload_encrypted()`, `mx_download_encrypted()`), and Olm-encrypted
to-device events of any type. It fixes the loss of inbound Olm messages
sent on a session the peer had opened earlier, and `mx_set_displayname()`
now returns the client it used so a caller can keep a refreshed token.

The mandatory mx.api floor is 0.4.0 and the optional mx.crypto floor is
0.3.0. Both versions are on CRAN.

## Suggested package outside the mainstream repositories

livekitr is in Suggests and is not on CRAN. It is available from the
repository declared in DESCRIPTION:

    Additional_repositories: https://cornball-ai.github.io/drat

Expect the incoming NOTE "Suggests or Enhances not in mainstream
repositories: livekitr". The check reports it as available through the
Additional_repositories specification.

livekitr carries only the media connection of a call. Every use is
conditional: `mx_call_connect()` calls `requireNamespace("livekitr")`
first and stops with an informative error when it is absent, and the
other call functions touch livekitr only on a session that
`mx_call_connect()` created. The Matrix side of a call
(`mx_call_join(connect = FALSE)`) works without it. No example, test, or
vignette needs livekitr; all checks below ran without it installed.

## API and compatibility

No exports were removed or renamed. `mx_send_encrypted()` gains an
optional `event_type` argument. `mx_crypto_process_sync()` adds a
`to_device` element to its result and keeps each decrypted room event's
`type` and `content`.

`mx_set_displayname()` returned `TRUE` invisibly and now returns the
client config invisibly. Neither reverse dependency uses the value.

Session stores written by 0.2.1 load unchanged: a single inbound Olm
session per peer becomes a one-element list.

## Test environments

All local checks used a library built from CRAN source packages only,
with mx.api 0.4.0 and without livekitr.

* Ubuntu 24.04.5, R 4.6.1: R CMD check --as-cran --run-donttest,
  including PDF and HTML manuals, examples, tests, and rebuilt vignettes,
  with mx.crypto 0.3.0 installed. Status: OK.
* The same check with mx.crypto also absent. Status: OK.
* Installed test suite with an empty HOME: 986 assertions passed and no
  file was written under HOME.
* win-builder, Windows Server 2022, R-release 4.6.2: Status: 1 NOTE, the
  livekitr NOTE described above. That run also reported a redirect for
  the drat URL in NEWS.md, which now has its trailing slash.
* GitHub Actions, ubuntu-latest and macos-latest, R 4.6: Status: OK.
* R-oldrelease was not checked for this release.

## Reverse dependencies

chat.api 0.1.0 and corteza 0.7.1, both reverse Suggests from CRAN, were
checked against the 0.3.0 tarball. Both: Status: OK.

## Examples

The call and encrypted-media examples are in \dontrun because they need
account credentials, a live Matrix homeserver, and for media a LiveKit
service. All executed example and test writes use temporary directories.
