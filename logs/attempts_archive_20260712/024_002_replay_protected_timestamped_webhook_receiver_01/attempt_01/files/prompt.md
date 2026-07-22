Write me an Elixir module called `WebhookReceiver` that implements a Plug-based HTTP endpoint for receiving webhook payloads using **replay-protected, timestamped HMAC-SHA256 signatures** (the Stripe `t=...,v1=...` scheme).

I need these modules:

1. `WebhookReceiver.Signature` — a module with:
   - `sign(timestamp, payload, secret)` — compute HMAC-SHA256 of the string `"<timestamp>.<payload>"` using `secret` and return it hex-encoded (lowercase).
   - `parse(header)` — parse a signature header of the form `"t=1700000000,v1=abcdef..."` into a map like `%{"t" => "1700000000", "v1" => "abcdef..."}`. Return `%{}` for anything that is not a binary.

2. `WebhookReceiver.Store` — a behaviour with callbacks:
   - `store_event(store, event_id, payload)` — persist with status `:pending`; `{:ok, :duplicate}` if the id already exists, `{:ok, :created}` if new.
   - `get_event(store, event_id)` — `{:ok, event}` or `:error`.
   - `all_events(store)` — all stored events as a list.

3. `WebhookReceiver.MemoryStore` — a GenServer implementing the behaviour with an in-memory map. Each event is a map with at least `:event_id`, `:payload` (decoded map), and `:status` (`:pending` on creation).

4. `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/stripe`. Options:
   - `:secret` — the HMAC signing key (required).
   - `:store` — the store process (required).
   - `:tolerance` — max allowed clock skew in seconds (default `300`).
   - `:now` — either an integer Unix-second timestamp or a 0-arity function returning one, used as "current time" (default `System.system_time(:second)`).

Router behaviour:
- Read the raw body once and the `stripe-signature` header.
- If the header is missing/empty, unparseable, or the signature does not match, return **401** with `{"error": "invalid_signature"}`.
- If the header's timestamp is outside the tolerance window (`abs(now - t) > tolerance`), return **401** with `{"error": "timestamp_expired"}` (check this before rejecting on signature mismatch).
- On a valid, in-window signature, decode the JSON, extract the `"id"` field:
  - already stored → **200** `{"status": "duplicate"}`
  - new → store and **200** `{"status": "received"}`
- Malformed JSON or missing `"id"` → **400** `{"error": "bad_payload"}`.

The raw body must be available for both signature verification and JSON decoding. Use only Plug and Jason (plus `:crypto` from OTP). No Phoenix, no Ecto. Give me all modules in a single file.