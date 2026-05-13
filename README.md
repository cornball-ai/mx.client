# mx.client

Stateful Matrix client helpers for R.

`mx.api` owns raw Matrix Client-Server HTTP endpoints. `mx.crypto`
owns Olm and Megolm primitives. `mx.client` is the layer between them:
local configuration, room resolution, sync cursor handling, event
extraction, invite acceptance, and eventually encrypted-room
orchestration.

