Write me an Elixir module called `WebhookReceiver` that implements a Plug-based HTTP endpoint for receiving webhook payloads with HMAC-SHA256 signature verification **and ordered, per-stream delivery with gap buffering**.

Each webhook belongs to a logical stream and carries a monotonically increasing sequence number. Events must be applied strictly in order per stream; an out-of-order (future) event is buffered until the gap fills, then drained.

I need these modules:

1. `WebhookReceiver.Signature` — `verify(payload, signature, secret)` computes lowercase hex HMAC-SHA256 of the raw `payload` and constant-time compares to `signature`. Returns `:ok` or `:error` (non-binary input → `:error`).

2. `WebhookReceiver.Store` — a behaviour with callbacks:
   - `deliver(store, event)` where `event` is a map with `:event_id`, `:stream_id`, `:sequence`, `:payload`, `:status`. Per stream it tracks the last delivered sequence (starting at `0`). Returns:
     - `{:ok, :received}` when `sequence == last_seq + 1` (deliver it, then drain any consecutive buffered events).
     - `{:ok, :duplicate}` when `sequence <= last_seq`, or when that exact sequence is already buffered.
     - `{:ok, :buffered}` when `sequence > last_seq + 1` (store it for later).
   - `last_sequence(store, stream_id)` — the last delivered sequence (default `0`).
   - `delivered_events(store, stream_id)` — delivered events in delivery order.
   - `buffered_sequences(store, stream_id)` — sorted list of currently-buffered sequence numbers.

3. `WebhookReceiver.MemoryStore` — a GenServer implementing the behaviour. Delivered events should have `:status` `:delivered`; buffered events `:status` `:pending`. Draining must apply buffered events in ascending, gapless order and stop at the first gap.

4. `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/stripe`. Options `:secret` and `:store`.
   - Read the raw body once and the `stripe-signature` header; missing/empty header or bad signature → **401** `{"error": "invalid_signature"}`.
   - Decode the JSON and require `"id"` (string), `"stream_id"` (string), and `"sequence"` (integer). Any missing/wrong-typed field or malformed JSON → **400** `{"error": "bad_payload"}`.
   - Build the event and call `deliver/2`:
     - `:received` → **200** `{"status": "received"}`
     - `:duplicate` → **200** `{"status": "duplicate"}`
     - `:buffered` → **202** `{"status": "buffered"}`

Use only Plug and Jason (plus `:crypto`). No Phoenix, no Ecto. Give me all modules in a single file.

## Additional interface contract

- `WebhookReceiver.Store` is not just a behaviour definition: it must ALSO define public client functions with the same names and arities as its callbacks, each dispatching to the given store process (e.g. via `GenServer.call(store, ...)`), so callers can invoke e.g. `WebhookReceiver.Store.last_sequence(store, stream_id)` directly on the module.
