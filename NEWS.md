# mx.client 0.1.1.3

* **HIGH** (security): homeserver-supplied keys are now verified before
  use. `mx_crypto_known_devices()` checks each device's Ed25519
  self-signature with `mx.crypto::mxc_verify_device_keys()`, and
  `mx_crypto_claim_otks()` checks each claimed one-time key with
  `mx.crypto::mxc_verify_one_time_key()` against that verified Ed25519.
  Both previously read the keys straight out of the response, so a
  malicious or compromised homeserver could substitute its own
  Curve25519 key for any device and read everything sent to that user.
  A device that fails verification is dropped with a warning and the
  remaining devices still receive the message.
* **HIGH** (security): Olm to-device payloads now carry the
  `sender`, `recipient`, `recipient_keys`, and `keys` fields the spec
  requires. `mx_crypto_room_key_payload()` emitted only `type` and
  `content`, leaving the receiver nothing to authenticate against;
  other clients reject such payloads.
* **HIGH** (security): `mx_crypto_process_sync()` and
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
  decrypt but always get `sender_verified = FALSE`, as do events
  decrypted with a session from a store written before this change.
* `mx_crypto_room_key_payload()` gains `sender_user_id`,
  `sender_ed25519`, `recipient_user_id`, and `recipient_ed25519`;
  `mx_crypto_encrypt_for_devices()` gains `sender_user_id` and now
  requires each recipient to carry a verified `ed25519`;
  `mx_crypto_handle_to_device()` gains `self_id`, `self_ed25519`, and
  `devices`, and its result carries `sender_bound`.
* Session stores written before this release still load: a bare
  `megolm_in` pickle is read as a session with no attested sender
  rather than discarded, so a running client keeps its history.
* `Suggests: mx.crypto (>= 0.2.0)`, the first version providing the
  verification helpers.
* New `inst/tinytest/test_transport.R` covers the verification paths
  against tampered fixture responses. `R/transport.R` previously had no
  test file at all.

# mx.client 0.1.1.1

* `mx_extract_text_events()` keeps the event's `origin_server_ts` as a
  `ts` field (milliseconds since the epoch, NULL when the server omits
  it). Records previously carried no time at all, leaving consumers to
  stamp messages with their own poll clock.

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
