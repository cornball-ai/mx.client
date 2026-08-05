# mx.client 0.2.0.3

## New

* `mx_extract_reactions()` returns every `m.reaction` in a sync as a
  record carrying `room_id`, `event_id` (the reaction, not its target),
  `sender`, `is_self`, `target_event_id`, `key`, and `ts`. It is the
  general form of `mx_extract_reaction_verdict()`, which answers one
  approve/deny question about one event with the key semantics baked in;
  that stays for callers who want it. Only additions are reported --
  removing a reaction is a redaction of the `m.reaction` event, which a
  consumer that needs to notice un-reactions has to read itself.

* `mx_extract_text_events()` records now carry `relates_to`, the event's
  `m.relates_to` content verbatim. It is what distinguishes a threaded
  reply from a rich reply from an edit, and dropping it left every caller
  unable to tell any of them from an ordinary message.

# mx.client 0.2.0.2

## Security

* **HIGH**: `mx_send_encrypted()` filtered its own device by `device_id`
  alone. Matrix device ids are scoped to a user, not globally unique, so
  every other account whose device happened to share the name was
  dropped from the recipient list -- two bots both called `BOT`, and the
  only recipient disappears while the send still returns an event id.
  The self-filter now compares `(user_id, device_id)`.

* **HIGH**: an encrypted send with no usable recipients posted the
  `m.room.encrypted` event anyway. Devices are skipped when their keys
  or one-time keys do not verify, which is deliberate, but skipping all
  of them means the room key reaches nobody and the caller is handed an
  event id for a message every recipient will fail to decrypt. Reaching
  zero now aborts. A room with no other devices at all is unaffected:
  that is a room of one, and sending to it is fine.
  The guard counts what the homeserver named, not what survived
  verification: counting survivors made a room whose only other device
  is malformed indistinguishable from a room with no other device, and
  only the second is safe to send to. `mx_crypto_verify_device_map()`
  reports every `(user_id, device_id)` it was given on a `seen`
  attribute so that distinction is available at all. An explicit
  `recipients = list()` is refused too, since supplying recipients skips
  discovery and every guard with it.

* **HIGH**: `/keys/query` and `/keys/claim` answer 200 with a `failures`
  map when a server could not be reached, returning whatever they did
  manage. Both were read as though the successful half were the whole
  answer, so an unreachable homeserver was indistinguishable from a user
  with no devices. `mx_crypto_known_devices()` and
  `mx_crypto_claim_otks()` gain `strict`: they warn by default and error
  under it, and `mx_send_encrypted()` asks for strict, because
  encrypting to a user whose devices could not be listed is how a
  message ends up readable by nobody.

# mx.client 0.2.0

## Security

* **HIGH**: homeserver-supplied keys are now verified before use.
  `mx_crypto_known_devices()` checks each device's Ed25519
  self-signature with `mx.crypto::mxc_verify_device_keys()`, and
  `mx_crypto_claim_otks()` checks each claimed one-time key with
  `mx.crypto::mxc_verify_one_time_key()` against that verified Ed25519.
  Both previously read the keys straight out of the response, so a
  malicious or compromised homeserver could substitute its own
  Curve25519 key for any device and read everything sent to that user.
  A device that fails verification is dropped with a warning and the
  remaining devices still receive the message.
* **HIGH**: Olm to-device payloads now carry the `sender`,
  `recipient`, `recipient_keys`, and `keys` fields the spec requires.
  `mx_crypto_room_key_payload()` emitted only `type` and `content`,
  leaving the receiver nothing to authenticate against; other clients
  reject such payloads.
* **HIGH**: `mx_crypto_process_sync()` and
  `mx_crypto_handle_to_device()` now confirm a decrypted Olm payload
  names this device as recipient before acting on it. Decrypting only
  proves the message was encrypted to our key, not that it was meant
  for us here, so a server could previously replay a captured payload.
* `mx_crypto_process_sync()` records the sender the Olm payload claimed
  when it shared each Megolm session, and drops any decrypted event
  whose cleartext envelope disagrees with that claim: the server was
  previously free to set `sender` to anything.
* `mx_crypto_process_sync()` and `mx_crypto_handle_to_device()` gain a
  `devices` argument taking the verified list from
  `mx_crypto_known_devices()`. A decrypted event reports
  `sender_verified = TRUE` only when the payload's claimed
  `(sender, ed25519, curve25519)` matches one of those devices as a
  triple. Agreement between the payload and the envelope is not enough
  on its own: a hostile homeserver writes both, so it can make them
  corroborate each other. Binding to a self-signed `device_keys` object
  is the part it cannot forge. Callers that pass no `devices` still
  decrypt but always get `sender_verified = FALSE`.

## Breaking changes

* `mx_crypto_room_key_payload()` requires four further arguments:
  `sender_user_id`, `sender_ed25519`, `recipient_user_id`, and
  `recipient_ed25519`. They are what the payload's authentication block
  is built from, so they have no defaults; a five-argument call now
  errors rather than silently emitting an unauthenticatable payload.
* `mx_crypto_encrypt_for_devices()` gains `sender_user_id` and now
  requires each recipient to carry a verified `ed25519`. Recipients
  from `mx_crypto_known_devices()` already do.
* `mx_crypto_handle_to_device()` gains `self_id`, `self_ed25519`, and
  `devices`; its result carries `sender_bound`.

## New

* `mx_table_html()` and `mx_send_table()` render a data frame, matrix,
  or list as the conservative Matrix table HTML that clients such as
  FluffyChat 2.6.0+ accept: a bare `<table>` of `<tr>`, `<th>`, and
  `<td>` nodes, with no CSS, colspan, rowspan, or custom attributes. A
  plain-text `body` is generated alongside for clients that ignore
  `formatted_body`.
* `mx_markdown_to_html()` converts GitHub-style pipe tables to the same
  table HTML, honouring the `:---`/`:---:`/`---:` alignment row.
* `mx_set_displayname(client, name)`: client-level wrapper over
  `mx.api::mx_set_displayname()` that builds the session from the client
  config and retries once through `mx_with_relogin()` on a rejected
  token, so long-running bots can rename themselves without
  hand-rolling session or relogin plumbing.
* `print()` method for `mx_client_config` masks `token` and `password`
  as `<hidden>` (or `<unset>` when empty) instead of falling through to
  the default list print, which showed credentials verbatim.
  `sync_token` and every other field stay visible; `unclass()` still
  exposes the raw values.

## Other

* `mx_extract_text_events()` keeps the event's `origin_server_ts` as a
  `ts` field (milliseconds since the epoch, NULL when the server omits
  it). Records previously carried no time at all, leaving consumers to
  stamp messages with their own poll clock.
* Session stores written before this release still load: a bare
  `megolm_in` pickle is read as a session with no attested sender
  rather than discarded, so a running client keeps its history. Events
  decrypted with such a session report `sender_verified = FALSE`.
* `Suggests: mx.crypto (>= 0.2.0)`, the first version providing the
  verification helpers.
* New `inst/skills/mx.client/matrix-messaging/SKILL.md`.
* New `inst/tinytest/test_transport.R` covers the key-verification
  paths against tampered fixture responses. `R/transport.R` previously
  had no test file at all.

# mx.client 0.1.1

* First release. Stateful client layer over 'mx.api': configuration
  persistence (`mx_client_load()`/`mx_client_save()`/`mx_client_configure()`),
  session construction (`mx_client_session()`), room resolution
  (`mx_resolve_room()`, `mx_room_lookup_by_name()`), sync cursor handling
  (`mx_sync_update()`), sync-event extraction (`mx_extract_text_events()`,
  `mx_extract_invites()`, `mx_extract_reaction_verdict()`), invite
  acceptance (`mx_accept_invites()`), text sending (`mx_send_text()`, with
  a `mentions` argument that sets `m.mentions` and rewrites textual
  `@localpart` into matrix.to pills via `mx_pill_mentions()`), and a
  conservative Markdown-to-HTML converter (`mx_markdown_to_html()`).
* End-to-end encryption orchestration over the optional 'mx.crypto'
  package: a pickled crypto store and account lifecycle
  (`mx_crypto_store_dir()`, `mx_crypto_account()`), signed device-key
  construction for upload (`mx_crypto_device_keys()`), Olm room-key
  sharing as to-device payloads (`mx_crypto_room_key_payload()`,
  `mx_crypto_handle_to_device()`, `mx_crypto_inbound_session()`), and
  Megolm event encrypt/decrypt (`mx_crypto_encrypt_event()`,
  `mx_crypto_decrypt_event()`). A loopback test exercises a full encrypted
  round-trip in-process.
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
