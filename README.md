# mx.client

Stateful Matrix client helpers for R.

`mx.api` owns the raw Matrix Client-Server HTTP endpoints. `mx.crypto`
owns the Olm and Megolm cryptographic primitives. `mx.client` is the
layer between them: local configuration, room resolution, sync cursor
handling, event extraction, invite acceptance, markdown-formatted
messages, and end-to-end encryption orchestration.

## Install

```r
# From GitHub while the CRAN submission is in flight:
remotes::install_github("cornball-ai/mx.client")

# Optional, for end-to-end encryption (needs a Rust toolchain to build):
install.packages("mx.crypto")
```

## Quick start: plaintext

```r
library(mx.client)

# One-time setup: log in, join the room, persist credentials
# (mode 0600, under tools::R_user_dir()).
mx_client_configure(
    server = "https://matrix.example.org",
    user = "bot",
    password = "secret",
    room = "#general:example.org",
    app = "myapp"
)

# Every later session:
client <- mx_client_load(app = "myapp")
mx_send_text(client, "hello from R")                       # default room
mx_send_text(client, "**bold** and `code`", room = "general",
             markdown = TRUE)                              # named room, HTML

# Poll for new messages and advance the stored sync cursor:
res <- mx_sync_update(client, timeout = 30000L)
msgs <- mx_extract_text_events(res$sync, client$user_id)
```

## Media, and surviving token rotation

Both need `mx.api (>= 0.3.0)`, which mx.client now pins.

```r
# Send a file with the stored client; the room resolves by name and the
# msgtype comes from the MIME type (a .png posts as m.image).
mx_send_media(client, "plot.png", room = "general")

# Recover from an invalidated access token without babysitting:
# catches M_UNKNOWN_TOKEN, re-logs in with the stored password
# (preserving the device id, so an E2EE identity survives), saves the
# refreshed token, and retries once.
mx_with_relogin(client, function(cl) {
    mx_send_text(cl, "still here after a token rotation")
})
```

## End-to-end encryption

Olm/Megolm send/receive orchestration over `mx.crypto`, aimed at bots
and controlled deployments. `mx.crypto` is a Suggests and is only called
from the E2EE entry points, so plaintext Matrix clients install and run
without a Rust toolchain.

The mental model: an *account* holds this device's identity keys, the
*store* persists everything on disk, *sessions* hold the live Olm (per
peer device) and Megolm (per room) ratchet state, and a *room key* is
what lets a device decrypt a room. mx.client moves all four around for
you.

```r
# Once: create the crypto store and publish this device's keys.
store <- mx_crypto_store_dir("myapp")
acct <- mx_crypto_account(store)
mx_crypto_publish_keys(client, acct, store)

# Send into an encrypted room. Device discovery, one-time-key claims,
# and Megolm key sharing happen inside.
sessions <- mx_crypto_sessions_load(store)
room_id <- mx_resolve_room(client, "secret plans")   # or a literal !id
res <- mx_send_encrypted(client, acct, sessions, room_id,
                         list(msgtype = "m.text", body = "secret"),
                         store, member_ids = "@friend:example.org")
sessions <- res$sessions

# Receive: recover room keys from to-device messages and decrypt
# timeline events in one pass.
my_curve <- mx.crypto::mxc_account_identity_keys(acct)$curve25519
sync <- mx_sync_update(client)$sync
out <- mx_crypto_process_sync(acct, sessions, sync,
                              my_curve, self_id = client$user_id,
                              self_device_id = client$device_id)
# Save ratchet state before network I/O. Mark only requests that were sent.
sessions <- out$sessions
mx_crypto_sessions_save(sessions, store)
sent <- list()
for (request in out$key_requests) {
    ok <- tryCatch({
        mx_crypto_send_key_requests(client, list(request)); TRUE
    }, error = function(e) FALSE)
    if (ok) sent[[length(sent) + 1L]] <- request
}
sessions <- mx_crypto_mark_key_requests_sent(sessions, sent)
mx_crypto_sessions_save(sessions, store)
for (cancel in out$key_request_cancellations) {
    try(mx_crypto_send_key_requests(client, list(cancel)), silent = TRUE)
}
out$events   # same shape as mx_extract_text_events()
```

Security model, in brief: self-signed device keys are checked before use;
cross-signing bootstrap verifies the master -> self-signing -> device chain;
and missing-session requests accept forwarded keys only from this user's
cross-signed devices. See `vignette("e2ee", package = "mx.client")`.

### Interactive verification from R

With mx.client >= 0.2.0.10 and mx.crypto >= 0.2.1.2, use the standard
Matrix SAS handshake to compare 7 emoji or 3 numbers with FluffyChat or
another compatible client. Each client keeps its own signing keys.

```r
# Stop any bot using this exact device before the console takes over sync.
client <- mx_client_load(path = config_path)
result <- mx_verify_console(client, existing_crypto_store,
    "@peer:example.org", "!room:example.org", exclusive = TRUE)
# On the peer's app, choose Start verification, then compare the displays.
# Restart the bot only after the console returns.
```

The R console can run over SSH on the bot's host while FluffyChat runs on
another computer. Both clients need their existing cross-signing identities;
FluffyChat may ask its owner to unlock its own signing keys. No FluffyChat
database access or transfer of private keys is needed. Confirmation is a
human action on both clients. Never send comparison values through the room
being verified or let an LLM confirm them.

The console consumes incoming messages while it owns sync and returns them
in `result$messages`; a paused bot will not automatically process those
messages. See the [E2EE vignette](vignettes/e2ee.md#interactive-sas-verification)
for existing-event-loop integration, failure handling, and completion checks.

If FluffyChat shows **Restore Crypto Identity** or the console reports
`peer_master_missing`, follow the [peer identity recovery guide](vignettes/e2ee.md#peer-identity-recovery-in-fluffychat).
It distinguishes device trust from account trust, identifies the right account
in a multi-account app, and separates recovery from an explicitly authorized
identity reset. Neither verification nor encrypted messaging requires access
to the other client's database.

### Procedural identity verification

With mx.client 0.2.0.10, `mx_crypto_verify_user()` signs another user's
independently authenticated master key and confirms the signature by
read-back. `mx_crypto_user_trust()` checks that directional trust without
writing. Run each as both accounts for mutual verification, using their
existing private signing keys. The [E2EE vignette](vignettes/e2ee.md#mutual-verification-from-an-r-console)
contains the console procedure and its key-pinning requirements.

### Recovering a missed room key

A signed device and a readable encrypted message are separate checks.
Cross-signing publishes a verifiable device identity; decryption also needs
the sender's Megolm room key. SAS verification does not recover missing history.

Since mx.client 0.2.0.9, incoming Olm messages are tried against both remotely
and locally initiated sessions. A peer can reply with a room key over the
session this client opened. Failed or replayed prekeys no longer abort the
whole receive batch. The receiving process must load the fixed version;
replacing package files does not update an already loaded R namespace.

If the sender keeps using a session whose key was missed before the fix,
rotate that sender's outgoing room session. In FluffyChat, send
`/discardsession` by itself in the affected room, then send a new test message
from the same client. This is a room-scoped command handled by FluffyChat's
[Matrix SDK](https://github.com/famedly/matrix-dart-sdk/blob/main/doc/commands.md).
A leave/rejoin or another message alone does not guarantee a new session.
Rotation preserves existing history but does not recover keys already missed.

Confirm that the receiver installs the new inbound Megolm session, reads the
test message, and replies with an `m.room.encrypted` event. A lock icon alone
does not establish a working round trip. Keep the existing device and crypto
store. See the [Matrix messaging skill's recovery procedure](inst/skills/matrix-messaging/SKILL.md#recovering-a-missed-room-key)
for safe inspection and recovery boundaries.

## The package family

| Package | Role | Depends on |
|---|---|---|
| [mx.api](https://github.com/cornball-ai/mx.api) | HTTP transport (CRAN) | — |
| [mx.crypto](https://github.com/cornball-ai/mx.crypto) | Olm/Megolm primitives (vodozemac) | — |
| mx.client | stateful client + E2EE orchestration | Imports mx.api, Suggests mx.crypto |
