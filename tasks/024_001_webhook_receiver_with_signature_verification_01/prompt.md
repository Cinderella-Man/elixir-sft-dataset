Write me an Elixir module called `WebhookReceiver` that implements a Plug-based HTTP endpoint for receiving webhook payloads with HMAC-SHA256 signature verification.

I need these modules:

1. `WebhookReceiver.Router` — a `Plug.Router` that exposes `POST /api/webhooks/stripe`. It should accept a `:secret` option (the HMAC signing key) and a `:store` option (a module implementing the storage behaviour). Parse the raw body, verify the signature from the `stripe-signature` header, and delegate to the store.

2. `WebhookReceiver.Signature` — a module with a single public function `verify(payload, signature, secret)` that computes HMAC-SHA256 of the raw payload string using the secret, and compares it (in constant-time) to the hex-encoded signature provided. Return `:ok` or `:error`.

3. `WebhookReceiver.Store` — a behaviour with two callbacks:
   - `store_event(store_pid, event_id, payload)` — persist the event with status `:pending`. If the event_id already exists, return `{:ok, :duplicate}`. If it's new, return `{:ok, :created}`.
   - `get_event(store_pid, event_id)` — return `{:ok, event}` or `:error`.
   - `all_events(store_pid)` — return all stored events as a list.

4. `WebhookReceiver.MemoryStore` — a GenServer implementing the `WebhookReceiver.Store` behaviour using an in-memory map. Each stored event should be a map with at least `:event_id`, `:payload` (the decoded map), and `:status` (always `:pending` on creation).

The router should behave as follows:
- Read the raw request body and the `stripe-signature` header.
- If the signature header is missing or verification fails, return 401 with a JSON body `{"error": "invalid_signature"}`.
- If verification passes, decode the JSON body, extract the `"id"` field as the event ID.
- If the event ID has already been stored, return 200 with `{"status": "duplicate"}`.
- If new, store it and return 200 with `{"status": "received"}`.
- If the JSON body is malformed or missing an `"id"` field, return 400 with `{"error": "bad_payload"}`.

The raw body must be read and kept available for both signature verification and JSON decoding. Use a custom body reader or cache the raw body in the conn's assigns.

Use only Plug and Jason as dependencies (plus :crypto from OTP). No Phoenix, no Ecto, no database drivers. Give me all modules in a single file.
