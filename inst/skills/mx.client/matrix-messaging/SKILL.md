---
name: matrix-messaging
description: >
  Send and receive Matrix messages from R using the mx.* package family
  (mx.api / mx.crypto / mx.client). Use when a user wants an R program or
  agent to post to a Matrix room, read new messages, accept invites, send
  files or tables, or talk to a Matrix homeserver. Posts go through
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
into an id (or passes a literal `!id`/`#alias` through); `mx_room_lookup_by_name()`
lists the joined rooms, which is how you find a DM (the room whose members
are just the bot and one person).

```r
room_id <- mx.client::mx_resolve_room(client, "general")
mx.client::mx_room_lookup_by_name(client)        # name -> id table
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
toolchain. Security model is trust-on-first-use (no cross-signing trust store
yet, no key-request flow). Check a room's state with `mx_room_encrypted()`
before choosing the encrypted or plaintext path.

The full flow (store, account, key publish, `mx_send_encrypted()`,
`mx_crypto_process_sync()`) and its current limitations are in
`vignette("e2ee", package = "mx.client")`.

## Report

End with: which identity (app/config) posted, which room, the message, and
the returned `event_id`.
