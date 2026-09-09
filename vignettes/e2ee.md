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

- **Verified device objects.** Every `/keys/query` device object must carry a
  valid Ed25519 self-signature. Cross-signed devices additionally require a
  valid master -> self-signing -> device chain. Trusting the master remains a
  user decision; an internally valid chain alone does not establish that the
  master belongs to the expected person.
- **Fail-closed bootstrap.** Cross-signing private keys are encrypted in the
  local crypto store. Bootstrap never resets an existing server identity when
  its private keys are absent or disagree.
- **Same-user key recovery.** Missing Megolm sessions generate durable,
  deduplicated `m.room_key_request` events. A forwarded key is accepted only
  for an outstanding request and only over Olm from this user's cross-signed
  device. Pass the locally trusted master to `mx_crypto_known_devices()` as
  `self_master_key`; without it, this user's devices are not cross-signed.
  This cannot recover another user's historical outbound session, and
  decrypted history from a forwarded key never reports its original sender as
  verified.
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

## Cross-signing bootstrap

Stop any other process using this device's crypto store, then load the same
persisted account and bootstrap its cross-signing identity:

```r
keys <- mx_crypto_cross_signing_bootstrap(
    client, acct, store,
    password = Sys.getenv("MATRIX_PASSWORD"))

devices <- mx_crypto_known_devices(client, client$user_id, strict = TRUE,
                                  self_master_key = keys$master)
mine <- Filter(function(device) {
    identical(device$device_id, client$device_id)
}, devices)
stopifnot(length(mine) == 1L, isTRUE(mine[[1L]]$cross_signed))
```

The password is used only when the homeserver requires password-based UIA and
must not be printed or embedded in source. A completed `auth` object can be
passed instead. Bootstrap saves the private master, self-signing, and
user-signing keys before uploading public objects. It is idempotent when the
local and server master keys agree and fails closed if the server identity has
no matching local private keys.
Valid device and master signatures already returned by `/keys/query` are
skipped on rerun.

Cross-signed is not the same as trusted. Another client must independently
verify the master identity before treating its signature chain as belonging to
the expected person.

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

signing <- mx_crypto_cross_signing_load(store)
master_pin <- if (is.null(signing)) NULL else
    mx.crypto::mxc_signing_key_public(signing$master)
# Include our own devices for history recovery, plus every encrypted sender
# in this sync for attribution. This example has one other participant.
devices <- mx_crypto_known_devices(
    client, c(client$user_id, "@friend:example.org"),
    self_master_key = master_pin)

my_curve <- mx.crypto::mxc_account_identity_keys(acct)$curve25519
out <- mx_crypto_process_sync(acct, sessions, res$sync, my_curve,
                              self_id = client$user_id,
                              self_device_id = client$device_id,
                              devices = devices)
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

for (ev in out$events) cat(ev$sender, ":", ev$body, "\n")
```

`mx_crypto_process_sync()` makes two passes over the sync response:

1. **To-device events**: Olm-decrypts anything addressed to this
   device's Curve25519 key. Direct `m.room_key` events become inbound
   Megolm sessions. Requested `m.forwarded_room_key` events are imported
   only after their request, sender, cross-signing chain, and computed
   session ID validate.
2. **Room timelines**: decrypts every `m.room.encrypted` event whose
   session is known. An unknown session creates one persistent request to
   the current user's other devices. Decrypted records match
   `mx_extract_text_events()` and add `sender_verified`.

Olm sessions carry messages in both directions. For each sender key, the
receiver tries the stored remotely initiated session (`olm_in`) and the
locally initiated session (`olm`). This applies to both normal and prekey
messages. If neither session decrypts, only a prekey can create a new
inbound session. Messages that cannot be decrypted or used to create a
session warn and are skipped, allowing the rest of the batch to proceed.
The two-map storage format is unchanged and retains only one session per
sender key in each map.

The lower-level `mx_crypto_handle_to_device()` accepts a list of existing
handles through `olm_sessions`. It advances a successful handle in place,
but does not retain a newly created session for the caller. Stateful clients
should use `mx_crypto_process_sync()` and save the returned sessions.
Undecryptable messages return `NULL` with a warning.

The caller saves returned crypto state before making any request transport
call. Successfully sent requests are then marked and saved again. Failed
requests remain queued with the same stable id and are returned again on later
polls; cancellation failures are safe to drop. This ordering prevents a
network error from replaying a sync batch against already-advanced Olm and
Megolm ratchets. The `chat.api` Matrix adapter performs this sequence
automatically and loads its own master pin from the local crypto store for
device queries. Sent requests with no answer currently remain stored until
their key arrives; automatic expiry/pruning is deferred.

## Persistence

Everything stateful lives in the crypto store directory:

| File | Holds |
|---|---|
| `pickle.key` | the locally stored 32-byte key the pickles are encrypted with |
| `account.pickle` | device identity (Curve25519 + Ed25519 keys, OTK state) |
| `sessions.json` | pickled Olm/Megolm sessions and outstanding key requests |
| `cross-signing.json` | encrypted master, self-signing, and user-signing private keys |

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
