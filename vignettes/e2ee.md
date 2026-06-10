<!--
%\VignetteEngine{simplermarkdown::mdweave_to_html}
%\VignetteIndexEntry{End-to-end encryption}
-->
---
title: "End-to-end encryption"
---

# End-to-end encryption

How to send and receive encrypted Matrix messages from R, and what each
step does on the wire. Code blocks here are display-only: the flow needs
a homeserver, a second device, and the `mx.crypto` package (which needs
a Rust toolchain to build).

`mx.crypto` provides the cryptographic primitives; `mx.client` keeps it
optional (Suggests) and only calls it from E2EE entry points, so
plaintext Matrix clients install and run without Rust.

## Security model

Read this first; it frames what the rest of the vignette delivers.

- **Trust on first use.** Device keys come from `/keys/query` and are
  used as-is. There is no cross-signing trust store yet, so a malicious
  homeserver could substitute device keys on first contact.
  (`mx.crypto` ships the verification primitives,
  `mxc_verify_device_keys()`; wiring a trust store is future work.)
- **No key requests or forwarded keys.** A device that missed the
  original `m.room_key` cannot ask peers to re-share it.
- **No SAS (emoji) verification.**
- **Local-key storage.** Ratchet state is pickled with a locally stored
  32-byte key (file mode 0600). That guards against casual inspection;
  it is only as strong as access to the local filesystem. No passphrase
  or hardware backing.

This matches what bots and controlled deployments need. For human-grade
verification flows, watch the `mx.crypto` roadmap.

## The pieces

Matrix encryption uses two ratchets, both provided by `mx.crypto`
(wrapping Matrix.org's `vodozemac`):

- **Olm** encrypts 1:1 between two *devices*. It is expensive to set up
  (a key agreement per peer device) and is used only to deliver secrets,
  chiefly Megolm session keys.
- **Megolm** encrypts room messages. One outbound session per room you
  send to; everyone you have shared its key with can decrypt.

So sending one encrypted room message means: have an Olm session with
each recipient device, send each of them your Megolm session key over
Olm (as *to-device* messages), then encrypt the actual message with
Megolm. mx.client orchestrates all of that; after one-time setup, a
send is one call and a receive is one call.

## Setup: a device with published keys

A Matrix *device* (a login session) gets long-lived identity keys plus a
pool of one-time keys others use to open Olm sessions with it. The
crypto store persists all of it (pickled with a locally stored 32-byte
key, mode 0600) so the device identity survives restarts.

```r
library(mx.client)

client <- mx_client_load(app = "myapp")    # see mx_client_configure()

store <- mx_crypto_store_dir("myapp")      # under tools::R_user_dir()
acct <- mx_crypto_account(store)           # load or mint identity keys
mx_crypto_publish_keys(client, acct, store, n_otks = 50L)
```

`mx_crypto_publish_keys()` builds the signed `device_keys` object,
signs and uploads one-time keys (`/keys/upload`), marks them published,
and saves the account. Run it again whenever the server's
`one_time_key_counts` runs low.

## Sending

```r
sessions <- mx_crypto_sessions_load(store)

res <- mx_send_encrypted(
    client, acct, sessions,
    room_id = "!abc:example.org",
    content = list(msgtype = "m.text", body = "the eagle lands at noon"),
    store_dir = store,
    member_ids = c("@friend:example.org")
)
res$event_id
```

On the wire, `mx_send_encrypted()`:

1. `/keys/query` — discovers the members' devices and identity keys
   (`mx_crypto_known_devices()`).
2. `/keys/claim` — claims a one-time key for each device we have no Olm
   session with (`mx_crypto_claim_otks()`), then opens the sessions.
3. `/sendToDevice` — Olm-encrypts the room's Megolm session key to each
   device that hasn't received it (`m.room_key` inside
   `m.room.encrypted`).
4. `/send` — Megolm-encrypts the actual content and posts the
   `m.room.encrypted` room event.
5. Persists the updated sessions to the store.

Steps 1–3 only do work the first time. Later sends to the same room are
a single Megolm encrypt + send.

## Receiving

```r
res <- mx_sync_update(client, timeout = 30000L)

my_curve <- mx.crypto::mxc_account_identity_keys(acct)$curve25519
out <- mx_crypto_process_sync(acct, sessions, res$sync, my_curve,
                              self_id = client$user_id)
sessions <- out$sessions
mx_crypto_sessions_save(sessions, store)

for (ev in out$events) cat(ev$sender, ":", ev$body, "\n")
```

`mx_crypto_process_sync()` makes two passes over the sync response:

1. **To-device events**: Olm-decrypts anything addressed to this
   device's Curve25519 key. Each recovered `m.room_key` becomes an
   inbound Megolm session, stored under `room_id|session_id`.
2. **Room timelines**: decrypts every `m.room.encrypted` event whose
   session is known, returning records in the same shape as
   `mx_extract_text_events()` — `room_id`, `event_id`, `sender`,
   `is_self`, `body`, `msgtype`, `mentions`.

Events whose keys haven't arrived yet are skipped, not errored; they
decrypt on a later pass once the to-device message lands.

## Persistence

Everything stateful lives in the crypto store directory:

| File | Holds |
|---|---|
| `pickle.key` | the locally stored 32-byte key the pickles are encrypted with |
| `account.pickle` | device identity (Curve25519 + Ed25519 keys, OTK state) |
| `sessions.json` | pickled Olm sessions and Megolm in/outbound sessions |

`mx_crypto_sessions_save()` / `mx_crypto_sessions_load()` round-trip the
session set, so an established room key keeps decrypting across process
restarts. One caution: the account binds to the config's `device_id`.
A homeserver will reject re-publishing different identity keys for an
existing device, so don't delete the store while keeping the login.

## Marking a room encrypted

Encryption is a room state event. Any member with permission can set it
(this is one-way; rooms don't downgrade to plaintext):

```r
s <- mx_client_session(client)
mx.api::mx_set_state(s, room_id, "m.room.encryption",
                     list(algorithm = "m.megolm.v1.aes-sha2"))
```

The boundaries of what this layer does are in the **Security model**
section at the top.
