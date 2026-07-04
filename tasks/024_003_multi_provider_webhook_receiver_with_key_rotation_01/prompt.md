Write me an Elixir module called `WebhookReceiver` that implements a Plug-based **multi-provider** webhook endpoint with HMAC-SHA256 signature verification and support for **secret rotation** (multiple simultaneously-valid keys per provider).

I need these modules:

1. `WebhookReceiver.Signature` — a module with:
   - `verify(payload, signature, secret, prefix \\ "")` — compute the lowercase hex HMAC-SHA256 of `payload` with `secret`, prepend `prefix` (e.g. `"sha256="`), and constant-time compare against `signature`. Return `:ok` or `:error`. Non-binary inputs return `:error`.
   - `verify_any(payload, signature, secrets, prefix \\ "")` — return `:ok` if `verify/4` succeeds for ANY secret in the `secrets` list, else `:error`.

2. `WebhookReceiver.Store` — a behaviour with callbacks:
   - `store_event(store, provider, event_id, payload)` — persist keyed by `{provider, event_id}` with status `:pending`; `{:ok, :duplicate}` if that provider/id pair exists, `{:ok, :created}` otherwise.
   - `get_event(store, provider, event_id)` — `{:ok, event}` or `:error`.
   - `all_events(store)` — all stored events as a list.

3. `WebhookReceiver.MemoryStore` — a GenServer implementing the behaviour. Each event is a map with at least `:provider`, `:event_id`, `:payload`, and `:status` (`:pending`).

4. `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/:provider`. Options:
   - `:providers` — a map from provider name (string) to a config map `%{secrets: [binary, ...], header: header_name, prefix: prefix}` where `prefix` is optional (default `""`). `secrets` is a list; the FIRST is current, later ones are being rotated out but still accepted.
   - `:store` — the store process (required).

Router behaviour:
- Look up `provider` from the path. If it isn't in `:providers`, return **404** `{"error": "unknown_provider"}`.
- Read the raw body once and the provider's configured signature header.
- Missing/empty header or no secret matches → **401** `{"error": "invalid_signature"}`.
- On success decode the JSON, extract `"id"`:
  - already stored for this provider → **200** `{"status": "duplicate"}`
  - new → store and **200** `{"status": "received"}`
- Malformed JSON or missing `"id"` → **400** `{"error": "bad_payload"}`.

Two different providers may share the same event id without colliding. Use only Plug and Jason (plus `:crypto`). No Phoenix, no Ecto. Give me all modules in a single file.