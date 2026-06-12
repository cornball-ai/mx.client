# mx.client 0.1.0.1 (dev)

* `mx_send_text()` gains a `mentions` argument: adds `m.mentions` user ids
  (so mentioned users are notified) and rewrites textual `@localpart` /
  `@localpart:server` into matrix.to pills in the HTML body. New exported
  helper `mx_pill_mentions()`.
* CRAN pre-submission pass: every exported function now has an example
  (runnable where no homeserver is needed, `\dontrun{}` otherwise, and the
  local crypto-store examples moved from `\dontrun{}` to guarded
  `\donttest{}`); added the `_PACKAGE` doc page; declared `stats` in
  Imports; tests redirect the `tools::R_user_dir()` roots to tempdir;
  `.claude` excluded from the build; the mx.crypto install hint now points
  at CRAN.

# mx.client 0.1.0

* First release. Stateful client layer over 'mx.api': configuration
  persistence (`mx_client_load()`/`mx_client_save()`/`mx_client_configure()`),
  session construction (`mx_client_session()`), room resolution
  (`mx_resolve_room()`, `mx_room_lookup_by_name()`), sync cursor handling
  (`mx_sync_update()`), sync-event extraction (`mx_extract_text_events()`,
  `mx_extract_invites()`, `mx_extract_reaction_verdict()`), invite
  acceptance (`mx_accept_invites()`), text sending (`mx_send_text()`), and a
  conservative Markdown-to-HTML converter (`mx_markdown_to_html()`).
* End-to-end encryption orchestration over the optional 'mx.crypto'
  package: a pickled crypto store and account lifecycle
  (`mx_crypto_store_dir()`, `mx_crypto_account()`), signed device-key
  construction for upload (`mx_crypto_device_keys()`), Olm room-key
  sharing as to-device payloads (`mx_crypto_room_key_payload()`,
  `mx_crypto_handle_to_device()`, `mx_crypto_inbound_session()`), and
  Megolm event encrypt/decrypt (`mx_crypto_encrypt_event()`,
  `mx_crypto_decrypt_event()`). A loopback test exercises a full encrypted
  round-trip in-process. Network wiring into `mx_send_text()`/
  `mx_sync_update()` follows.
* `mx_room_encrypted()` reads a room's `m.room.encryption` state (with
  the usual name/id/default resolution), so callers can pick the
  encrypted or plaintext send path before building one.
* Client-layer media sending: `mx_send_media()` resolves the room by
  name (or default), builds the session from the stored config, and
  uploads + posts in one call via `mx.api::mx_send_media()`.
* Token-rotation recovery: `mx_client_relogin()` refreshes the access
  token with the stored password while preserving the device id (so an
  E2EE device identity survives), and `mx_with_relogin()` wraps any
  client operation with a one-shot catch-and-retry on
  `M_UNKNOWN_TOKEN`, using mx.api's classed error conditions. Requires
  mx.api >= 0.3.0.
* All exported functions carry examples.
