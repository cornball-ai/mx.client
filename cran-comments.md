# cran-comments

## Submission

Update from CRAN version 0.2.0 to 0.2.1.

The Windows pre-flight candidate was numbered 0.3.0. It has been renumbered
to 0.2.1 for submission; its R code, examples, tests, and dependencies are unchanged.

This release adds interactive Matrix Short Authentication String (SAS)
verification, cross-signing bootstrap and pinned identity verification,
room-key requests and recovery, threaded messages, and richer sync-event
extraction. It fixes reception of Olm replies on locally initiated sessions,
rejects encrypted sends when no intended recipient can receive a key, and
validates crypto-store schema versions without changing the raw account
pickle format. Existing stores remain readable.

The mandatory mx.api floor is 0.3.0.2; CRAN version 0.3.1 satisfies it.
The optional mx.crypto floor is 0.2.2, now on CRAN, for SAS primitives.
Unencrypted client operations still work without mx.crypto.

## API and compatibility

No exports were removed or renamed. Existing functions gain optional
arguments; newly added functions cover SAS, cross-signing, key-request
bookkeeping, identity trust, and event extraction.

Decryptable own encrypted messages are now returned with is_self = TRUE,
as cleartext own messages already were. Forwarded room keys never mark
the original event sender verified. Failed to-device decryption warns and
skips the event instead of aborting the batch. Session stores gain a version
field; legacy stores load, and account.pickle remains a raw encrypted pickle
so older clients can continue to read it.

## Test environments

* Ubuntu 24.04.5, R 4.6.1: R CMD check --as-cran, including PDF and HTML
  manuals, examples with --run-donttest, tests, and rebuilt vignettes.
  Status: OK, 0 errors, 0 warnings, 0 notes.
* Full source suite: 792 assertions passed with mx.crypto 0.2.2 and
  mx.api 0.3.1. The 15 added or revised local examples also passed separately.
* GitHub Actions: Ubuntu and macOS passed on the merged 0.2.0.11 code.
  Release preparation changes only documentation and metadata; parsed R
  expressions are unchanged across all 24 source files.
* Windows R-devel (2026-09-10 r90519): Status OK, 682 test assertions.
  Store-schema tests were skipped because the worker's mx.crypto version
  was below 0.2.2. Report: https://win-builder.r-project.org/62jmaVSsW2vK/
* Windows R-release 4.6.1: 1 error, 1 warning. The worker's mx.crypto lacked
  the seven SAS exports, causing the dependency warning and SAS example
  error. Only 466 test assertions ran; SAS and store-schema tests were
  skipped. Report: https://win-builder.r-project.org/MvFXJ8kbX0Jp/
* On 2026-09-11 CRAN listed mx.crypto 0.2.2 source but still 0.2.1 Windows
  binaries. The Windows reports above used older dependencies and do not
  establish full Windows coverage. The local check and full source suite
  used the declared mx.crypto 0.2.2 dependency and passed.

## Reverse dependency

CRAN's corteza 0.7.1, a reverse Suggests dependency, was checked against
both CRAN mx.client 0.2.0 and the 0.2.0.11 candidate underlying this release.
Both runs passed installation, examples, tests, and vignette checks.
Both had the same incoming-feasibility warning because corteza 0.7.1 is
already on CRAN. There were no new errors or warnings from this update.

## Examples

The new SAS examples use synthetic in-memory identities and exchanges.
They do not connect to Matrix, inspect a user's crypto store, or upload
trust. Explicit refusal examples demonstrate that cancelled or unconfirmed
exchanges cannot grant trust. Local encrypt/decrypt examples are runnable.

The new cross-signing bootstrap example remains in \dontrun because it
requires account credentials, the existing device store, and a live Matrix
homeserver. Actual console verification additionally requires a human to
compare values on trusted displays. Other network examples remain guarded;
all executed example and test writes use temporary directories.
