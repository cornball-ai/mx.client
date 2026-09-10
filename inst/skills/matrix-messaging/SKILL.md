---
name: matrix-messaging
description: >
  Send and receive Matrix messages from R using the mx.* package family
  (mx.api / mx.crypto / mx.client). Use when a user wants an R program or
  agent to post to a Matrix room, read new messages, accept invites, send
  files or tables, troubleshoot missed E2EE room keys, or talk to a Matrix
  homeserver. Posts go through
  mx.client (config, room resolution, HTML formatting) over mx.api, never
  hand-rolled curl. End-to-end encryption is orchestrated over the optional
  mx.crypto package.
allowed-tools: Bash(r:*), Bash(Rscript:*), Read
---

# matrix-messaging

Drive a Matrix homeserver from R with the mx.* family. `mx.client` owns
config persistence, room resolution, sync cursors, event extraction, and
HTML formatting; it sits on `mx.api` (the raw Client-Server endpoints) and,
for encryption, `mx.crypto` (Olm/Megolm primitives).

Do not hand-roll curl against the homeserver. `mx.client` already owns
config loading, session construction, room resolution, and HTML formatting.

## The package family

| Package | Role | Notes |
|---|---|---|
| `mx.api` | HTTP transport, one function per CS-API endpoint, holds nothing | on CRAN; `mx.client` Imports it |
| `mx.crypto` | Olm/Megolm primitives (vodozemac via Rust) | on CRAN; `mx.client` Suggests it (E2EE only) |
| `mx.client` | stateful client: config, rooms, sync, formatting, E2EE orchestration | on CRAN |

## First-time setup

`mx_client_configure()` logs in, joins the room, and persists credentials
(mode 0600, under `tools::R_user_dir()`). `app` namespaces the stored
config so several bots can coexist. Do this once per identity.

```r
mx.client::mx_client_configure(
    server   = "https://matrix.example.org",
    user     = "bot",
    password = "secret",
    room     = "#general:example.org",   # default room for later sends
    app      = "myapp"
)
```

## Send a message

Every later session loads the stored config and sends. `markdown = TRUE`
adds a conservative HTML `formatted_body` (headings, bold, code, lists,
links, and GitHub pipe tables become Matrix `<table>` HTML). `room` takes a
name or id; omit it for the configured default. `mx_send_text()` returns the
event id.

```r
client <- mx.client::mx_client_load(app = "myapp")

mx.client::mx_send_text(client, "hello from R")                  # default room
id <- mx.client::mx_send_text(client, "**shipped** `v0.1.1`",
                              room = "general", markdown = TRUE)  # named room
```

Tokens stay in the config file. Never print them.

To load a config by explicit path instead of `app`, pass `path =`. Use
`dry_run = TRUE` to print the resolved send without hitting the network.

### Mentions

`mentions = "@user:example.org"` adds the user to the event's `m.mentions`
(so they get pinged) and rewrites any textual `@localpart` in the body into a
matrix.to pill. A pill implies an HTML body even without `markdown = TRUE`.

## Resolve rooms

Send by human name instead of `!opaque:id`. `mx_resolve_room()` turns a name
into an id (or passes a literal `!id` through). `mx_room_lookup_by_name()`
finds a joined room with the supplied display name, returning its id or NULL.

```r
room_id <- mx.client::mx_resolve_room(client, "general")
mx.client::mx_room_lookup_by_name(client, "general")
```

## Send files and media

`mx_send_media()` (needs `mx.api (>= 0.3.0)`) uploads and posts in one call.
The msgtype comes from the file's MIME type: a `.png` posts as `m.image`, a
`.mp4` as `m.video`. Server upload cap is about 20 MB
(`mx.api::mx_media_config()` to check). Pass `content_type =` for files whose
extension lies, and `body =` for a caption/filename.

```r
mx.client::mx_send_media(client, "plot.png", room = "general")
```

## Send a table

`mx_send_table()` renders a data frame (or matrix) straight to Matrix HTML
via `mx_table_html()`.

```r
mx.client::mx_send_table(client, head(mtcars), room = "general")
```

## Receive: read new messages and advance the cursor

`mx_sync_update()` long-polls and advances the stored sync cursor so you only
see new events. The `mx_extract_*` helpers parse the sync response.

```r
res    <- mx.client::mx_sync_update(client, timeout = 30000L)
msgs   <- mx.client::mx_extract_text_events(res$sync, client$user_id)
invs   <- mx.client::mx_extract_invites(res$sync)
mx.client::mx_accept_invites(client, invs)        # join rooms you were invited to
```

## Survive token rotation

`mx_with_relogin()` wraps any client operation: on `M_UNKNOWN_TOKEN` it
re-logs in with the stored password (keeping the device id, so an E2EE
identity survives), saves the refreshed token, and retries once.

```r
mx.client::mx_with_relogin(client, function(cl) {
    mx.client::mx_send_text(cl, "still here after a token rotation")
})
```

## End-to-end encryption

Olm/Megolm send/receive orchestrated over `mx.crypto`, aimed at bots and
controlled deployments. `mx.crypto` is a Suggests and is only touched from
the E2EE entry points, so plaintext clients install and run without a Rust
toolchain. Cross-signing bootstrap is fail-closed, and missing Megolm sessions
produce durable key requests that accept forwarded keys only from the same
user's cross-signed devices. Check a room's state with `mx_room_encrypted()`
before choosing the encrypted or plaintext path. SAS verification requires
mx.client >= 0.2.0.10 and mx.crypto >= 0.2.1.2; cross-user history recovery is absent.

The full flow (store, account, key publish, `mx_send_encrypted()`,
`mx_crypto_process_sync()`) and its current limitations are in
`vignette("e2ee", package = "mx.client")`.

### Interactive verification

Use the vignette's interactive SAS procedure and `mx_verify_console()` with
the exact existing config and crypto store. The console may run over SSH
while the peer uses FluffyChat on another computer. Do not extract another
client's database or private keys. The human compares and confirms both
displays; never pass SAS values through Matrix or have an LLM affirm them.

A standalone console requires approved exclusive ownership: stop the bot
using that device first and restart it after the console returns. It consumes
ordinary messages too, returning them for review rather than queueing them
for the paused bot. Existing hosts can use `verification_events` and SAS
callbacks in their sole event loop. Distinguish local trust read-back from
the peer's done acknowledgement and from live encrypted-message delivery.

For FluffyChat recovery, use the vignette's **Peer identity recovery in
FluffyChat** section. Confirm the full Matrix ID before opening recovery in
a multi-account app, and keep that account selected through authentication.
Use the existing encrypted DM; a 2-person room is not necessarily a DM.
A signed device, trusted account master, and readable encrypted conversation
are separate checks. Old device activity timestamps are not sufficient
evidence that a device is unavailable.

`peer_master_missing` is a failed account-identity proof even when emoji
match. Restore the peer's identity through its normal app first. Device-only
verification, including skipping a recovery prompt, cannot recreate absent
signing keys. **Restore Crypto Identity** can also mean a missing backup
secret, not loss of all signing keys. Never weaken the master-MAC check.
If recovery is unavailable, explain the history/trust consequences and get
explicit owner approval before a crypto-identity reset. Preserve the login,
device, and local room keys; do not use **Export session and wipe device**.
The password authorizing new identity keys is the Matrix account password,
not the computer password or backup passphrase. Keep all secrets local.
Reset the selected account only once; other sessions should restore the new
identity, not reset again. Encrypted messages appearing on another session
without a fresh login do not prove signing-key recovery. Retry SAS with a
fresh request, inspect `phase`, `local_trust_recorded`, and `peer_done`, then
test a new message after the console exits and the bot resumes.

### Procedural mutual verification

mx.client >= 0.2.0.10 provides `mx_crypto_user_trust(client, store_dir,
user_id, master_key)` for a read-only directional trust check and
`mx_crypto_verify_user()` with the same arguments to upload and confirm a
trust signature. Use the vignette's mutual-verification console procedure.
Preflight both identities before either upload; verify each direction from
its own account. Another user's user-signing key is not publicly queryable.

Require the full peer master key authenticated through a trusted independent
channel. Copying `/keys/query` into the expected-key argument is not identity
verification. Preserve existing identities: if a client's private signing
key is unavailable, ask its owner to unlock it through that client. Do not
reset cross-signing, extract recovery secrets into chat, or claim mutual
verification from one successful signature. The uploads are not atomic;
report partial success and recheck before retrying.

The new `identity_verified` device metadata requires the trust signature and
device chain. It does not change recipient policy or the older
`sender_verified` field, which attests device binding rather than user trust.

### Recovering a missed room key

Keep three checks separate: cross-signing validates a device's signature
chain against a trusted master; decryption requires the sender's Megolm room
key; interactive SAS verification authenticates keys. A signed-device badge
or an encrypted-room icon does not prove the receiver can read a message.
Use the vignette's bootstrap procedure when cross-signing is actually needed;
preserve the existing account and use its local master pin for chain checks.

For a receiver that sends encrypted messages but cannot read replies:

1. Verify the package path/version loaded by the receiving process. mx.client
   0.2.0.9 fixes receipt over a locally initiated Olm session: both stored
   directions are tried for normal and prekey messages before guarded inbound
   creation. With deployment approval, stop affected consumers before replacing
   a shared R package, then restart them. An installed version check alone
   does not prove an older process loaded it.
2. Inspect the actual room and sender device. Read recent room-history metadata
   with `mx.api::mx_messages(mx.client::mx_client_session(client), room_id)`
   and compare the event's `session_id` with persisted `megolm_in` and
   `key_requests`. Read metadata from the exact store the application uses;
   do not guess a store path or construct a new account for inspection.
   An unchanged sync cursor can mean no new events. Also, `olm_in` can stay
   empty while replies decrypt through sessions in `olm`; check the relevant
   inbound Megolm session and plaintext, not one map's count.
3. If new messages reuse a session whose key was missed, ask the sender to
   rotate that room's outgoing session. In FluffyChat, the sender enters
   `/discardsession` as a standalone command in the affected room, then sends
   a new short message from that same client. This command is interpreted by
   the sender's app, not by the bot or an R console. It resets that room's
   outgoing group session; it does not reset the account or delete history.
   See the [Matrix Dart SDK command documentation](https://github.com/famedly/matrix-dart-sdk/blob/main/doc/commands.md).
   Do not assume a leave/rejoin or another message rotated the session:
   compare session IDs. Rotation supplies a new session for future messages;
   it does not recover a missing historical key.
4. Verify a new session ID, its matching persisted inbound Megolm key, the
   expected decrypted test text, and (for a replying bot) an encrypted reply
   visible to the sender. If one rotation attempt still leaves the key missing,
   inspect key delivery and sender policy before asking for further resets.

Do not run a second `/sync` consumer or save crypto state from a diagnostic
console while the bot owns that device. Room-history queries do not consume
the to-device queue. Do not rewind sync, delete the crypto store, or weaken
forwarded-key admission to make the test pass. Key requests in this stack go
to the bot's own devices and accept forwarded keys only from its cross-signed
devices; with no such device holding the old key, that request cannot recover
the old session. Keep deployment identities, room IDs, and incident logs out
of public package documentation.

## Report

End with: which identity (app/config) posted, which room, the message, and
the returned `event_id`.
