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
                              my_curve, self_id = client$user_id)
out$events   # same shape as mx_extract_text_events()
```

Security model, in brief: device keys are trusted on first use (no
cross-signing trust store yet), and there is no key-request or
forwarded-key flow. See `vignette("e2ee", package = "mx.client")` for
the full flow, what happens on the wire, and the current limitations.

## The package family

| Package | Role | Depends on |
|---|---|---|
| [mx.api](https://github.com/cornball-ai/mx.api) | HTTP transport (CRAN) | — |
| [mx.crypto](https://github.com/cornball-ai/mx.crypto) | Olm/Megolm primitives (vodozemac) | — |
| mx.client | stateful client + E2EE orchestration | Imports mx.api, Suggests mx.crypto |
