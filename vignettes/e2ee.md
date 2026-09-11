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
- **Interactive SAS verification.** With mx.crypto >= 0.2.1.2, an explicit
  human comparison and valid MACs authenticate a fixed snapshot of both
  device and master keys. Trust signatures are uploaded and checked only
  after those requirements pass. QR verification is not implemented.
- **Local-key storage.** Ratchet state is pickled with a locally stored
  32-byte key (file mode 0600). That guards against casual inspection;
  it is only as strong as access to the local filesystem. No passphrase
  or hardware backing.

The console procedure below uses the same Matrix verification messages as
other clients. It does not require access to their private databases.

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

## Interactive SAS verification

Requires mx.client >= 0.2.0.10 and mx.crypto >= 0.2.1.2. Older crypto builds
can still perform existing E2EE operations, but the SAS entry points refuse
with an upgrade message. The handshake negotiates `m.sas.v1`,
`curve25519-hkdf-sha256`, `sha256`, and `hkdf-hmac-sha256.v2`. It supports
in-room and to-device requests, emoji and decimal displays, cancellation,
timeouts, simultaneous starts, commitment checks, and both device/master MACs.

For a bot, stop the service that owns its Matrix device. Open an interactive
R console on that host, load its exact existing config and crypto store,
and run:

```r
client <- mx_client_load(path = config_path)
result <- mx_verify_console(client, existing_crypto_store,
    "@peer:example.org", "!room:example.org", exclusive = TRUE)
```

`config_path` and `existing_crypto_store` are paths supplied by the operator,
not new stores. Cross-signing must already be bootstrapped for this identity.
The function refuses missing stores or mismatched local/published keys. It
does not create accounts, reset keys, change room membership, or read a
FluffyChat database. The other user's app can run on another computer; an
SSH terminal is sufficient for the R side. That app owns its own signing
keys and may ask its user to unlock them through its normal interface.

In the peer's app, choose **Start verification**. Accept in R, compare all
7 emoji (with labels) or all 3 numbers against the app, and explicitly
confirm in both interfaces. Empty input is rejection. Compare in person,
on your own two screens, or over a trusted independent channel. Never put
the comparison in the Matrix conversation being verified. An LLM must not
supply the confirmation. A peer that authenticates only its device key,
without its master key, is refused for cross-user verification. For another
device of this same account, its device MAC is sufficient: this account
already has a trusted local master and signs the newly authenticated device.
Some clients omit their own master proof until that identity is locally
verified. If the console reports `cancel_detail = "peer_master_missing"`,
restore or verify the existing identity through that client's normal recovery
interface before retrying. Matching emoji alone do not authenticate an omitted
master key. Never accept an unproven master or reset an identity implicitly.
An owner-approved identity replacement is a separate recovery decision,
described below.

After the call returns, inspect `result$status`. `local_trust_recorded`
means this account's signature was confirmed by read-back. `peer_done`
means the other client acknowledged completion; it is not a read-back of
the other user's private user-signing key. A cancelled or timed-out flow
can still have recorded local trust if cancellation happened after that
upload. Report that partial state, then recheck before repeating. Interrupted
ephemeral handshakes cannot be restored; start a new verification request.
Each console attempt reloads its saved config so a reused R client object
cannot rewind the cursor to an earlier attempt. Changed server, user, or
device identities are refused before network or crypto-store operations.

Restart the bot only after the console returns. `exclusive = TRUE` asserts
that you stopped other consumers; it is not a process lock. The console
advances the same cursor after saving crypto state. Ordinary messages read
during the session are passed to `on_messages` and returned in
`result$messages`. The default reports counts rather than interleaving
untrusted chat text with the verification prompts. A paused bot will not
automatically process those messages. This is a temporary console takeover,
not an always-on bot verification UI.

### Peer identity recovery in FluffyChat

These steps describe the FluffyChat 2.9.1 interface with Matrix Dart SDK
10.2.0. Labels and recovery behavior may differ in other builds.

Start in the correct account and room. In a multi-account app, close any open
recovery page, select the intended account, and confirm its full Matrix ID in
Settings before reopening **Chat backup**. Keep that account selected through
any authentication prompt. FluffyChat exposes **Start verification** in an
encrypted direct chat; a room with 2 members is not necessarily marked as a
direct chat. Use the existing DM with the peer. Do not create a new room or
enable encryption merely to make a missing button appear.

The app displays several independent states:

| Display | What it establishes |
|---|---|
| Signed or verified device | Trust in that device's keys, not necessarily recovery of the account's signing keys. |
| Verified account identity | Trust in the account's master key. Cross-user SAS authenticates this key as well as the device. |
| Known since | When the identity was first seen, not independent authentication. |
| Encrypted room | Encryption is enabled; a readable new message and reply are separate delivery checks. |

**Restore Crypto Identity** means required recovery secrets are unavailable
locally. It can reflect a missing backup secret even when some signing keys
are present. It does not prove all keys are lost. First use the existing
recovery key or passphrase, or another device that still has the identity.
If automatic verification does not appear, inspect **Settings → Devices**
and start verification with the specific other device. A verified-device
badge does not prevent that action. Compare and confirm on both screens.
Skipping a recovery prompt may permit device-only verification; it does not
recreate missing signing keys. Device names need not identify a unique host,
and an old **Last active** timestamp alone does not prove a device is unused.

If no recovery route works, the account owner may separately authorize a
new crypto identity after accepting the history and trust consequences.
In the interface above, the route is **Settings → Chat backup → Restore
Crypto Identity → Reset account**, followed by the crypto-identity reset
screen. Confirm that it is the crypto identity being reset, not account
deletion. This replaces the cross-signing keys, secret storage, and backup
version. It preserves the current login, device, and locally held room keys;
existing local room keys are queued for the new backup. History whose keys
exist only in an inaccessible old backup may remain unreadable. Do not use
**Export session and wipe device** for this procedure.

| Credential | Purpose |
|---|---|
| Matrix account login password | Authorizes publishing replacement identity keys when the server asks for password authentication. |
| Crypto recovery key or backup passphrase | Opens the account's encrypted secret storage. Save the new recovery material securely after a reset. |
| Computer or desktop keyring password | Opens local operating-system storage; it is not the Matrix login password. |

Keep these credentials local. Do not paste them into chat or a task record.
Reset only the selected account, once. Other sessions of that account should
restore the new identity using the new recovery material, not reset it again.
Another account in the same app must remain untouched. Existing sessions may
continue reading encrypted conversations without logging in again; that
does not establish that they have recovered the new signing keys.

After the peer's identity is ready, use a fresh verification request in the
R console. Load the intended package builds and retain the existing config,
device, and store. Do not rewind sync or delete state after a cancellation.
After matching and confirming on both screens, inspect:

```r
result$status[c("phase", "local_trust_recorded", "peer_done")]
# Expected completion: phase "done", local_trust_recorded TRUE, peer_done TRUE.
```

This confirms local trust read-back and the peer's completion acknowledgement,
not independent inspection of the peer's private signing state. End the
console takeover before restarting the bot, then send a new normal message
and confirm a readable reply. That tests live delivery separately from SAS.
Messages consumed during console verification are in `result$messages` and
will not automatically replay to the bot.

### Integrating an existing event loop

`mx_crypto_process_sync()` returns original verification envelopes in
`verification_events`, separate from normalized chat messages. Save its
account/session state and cursor before any verification transport or trust
upload. Create a transaction with `mx_sas_from_request()` and pass further
events to `mx_sas_receive()`. `mx_sas_outgoing()` exposes a stable outbox;
acknowledge each id only after a successful send. In encrypted rooms retain
the original event type using `event_type` in the encryption helpers, and
carry `m.relates_to` outside the ciphertext too.

`mx_sas_console(sas, receive, send, complete)` supplies the trusted human
prompts around those hooks. `receive` must use the application's existing
consumer; do not add a second `/sync` reader. `complete` calls
`mx_sas_record_trust()` only after explicit comparison and peer MAC checks.
Keep a transaction in memory, expire stale transactions, and cancel multiple
simultaneous requests from the same peer. SAS success does not change
forwarded-key admission or make missing historical room keys available.

## Mutual verification from an R console

With mx.client 0.2.0.10, two existing identities can verify each other without
an emoji exchange. Authenticate each full master public key through a trusted
independent channel, such as the other account's locally controlled console.
Do not copy the key from `/keys/query` and pass it back as its own proof.
The [Matrix cross-signing specification](https://spec.matrix.org/latest/client-server-api/#cross-signing)
defines user-to-user trust as a user-signing signature on the other master.

The following assumes `alice` and `bob` are existing client configs, their
stores already contain the matching private cross-signing keys, and
`alice_pin` and `bob_pin` have been authenticated independently. It does not
log in, generate identities, or recover another application's private keys.

```r
# Preflight both sides before making either trust change.
a <- mx_crypto_user_trust(alice, alice_store, bob$user_id, bob_pin)
b <- mx_crypto_user_trust(bob, bob_store, alice$user_id, alice_pin)

# Each account signs separately with its own existing user-signing key.
mx_crypto_verify_user(alice, alice_store, bob$user_id, bob_pin)
mx_crypto_verify_user(bob, bob_store, alice$user_id, alice_pin)

a <- mx_crypto_user_trust(alice, alice_store, bob$user_id, bob_pin)
b <- mx_crypto_user_trust(bob, bob_store, alice$user_id, alice_pin)
stopifnot(isTRUE(a$verified), isTRUE(b$verified))
```

The check is read-only. The verifier uploads only a missing or invalid public
signature, then verifies its read-back; it never saves ratchet state, runs
`/sync`, or changes the local identity. The two uploads are not atomic: if the
second fails, the first can remain recorded. Recheck both sides and rerun
with the same independently authenticated pins. A replaced identity requires
a new explicit authentication decision, not an automatic re-pin.

If one account belongs to another client, unlock and use that client's
existing signing keys through a supported path. A password or access token
alone cannot supply its private user-signing key. Do not reset its identity
or send its recovery key through chat to complete this procedure.

`mx_crypto_known_devices(..., self_master_key = alice_pin)` reports
`identity_verified` only when a device's self-signing chain reaches a master
authenticated by Alice's pin and trust signature. Unsigned devices remain
unverified even when their account's master is trusted. This field does not
change the existing recipient policy, `sender_verified` device-binding
semantics, or same-user-only forwarded-room-key admission. No SAS transaction
is completed, so an already-open interactive verification dialog is separate.

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

From mx.client 0.2.0.11, all 3 store files declare schema version 1.
Unknown or malformed versions are rejected before unpickling. This is the
mx.client file format version, not the mx.crypto package version.
Unversioned `sessions.json` and raw base64 `account.pickle` files remain
readable and are migrated on the next save, never by a read-only load.
Cross-signing files have always required an explicit version.

New `account.pickle` files use a JSON envelope around the encrypted pickle.
Clients older than 0.2.0.11 cannot read that envelope. Back up the whole store
before upgrading; preserve that backup if an older client may need to resume.

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
