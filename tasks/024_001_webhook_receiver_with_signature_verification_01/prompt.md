# Ticket: `WebhookReceiver` — Plug webhook endpoint with HMAC-SHA256 signature verification

Deliver an Elixir module `WebhookReceiver` implementing a Plug-based HTTP endpoint that receives webhook payloads with HMAC-SHA256 signature verification. All modules in a single file.

**Modules required**

- `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/stripe`.
  - Accept a `:secret` option (the HMAC signing key) and a `:store` option (a module implementing the storage behaviour).
  - Parse the raw body, verify the signature from the `stripe-signature` header, delegate to the store.
- `WebhookReceiver.Signature` — single public function `verify(payload, signature, secret)`.
  - Compute HMAC-SHA256 of the raw payload string using the secret.
  - Compare it, in constant-time, to the hex-encoded signature provided.
  - Return `:ok` or `:error`.
  - Hex encoding is lower-case.
  - A signature that is not valid hex (garbage input) must return `:error`, not raise.
- `WebhookReceiver.Store` — a behaviour with these callbacks:
  - `store_event(store_pid, event_id, payload)` — persist the event with status `:pending`. If the event_id already exists, return `{:ok, :duplicate}` and leave the already-stored event unchanged (do not overwrite its payload). If new, return `{:ok, :created}`.
  - `get_event(store_pid, event_id)` — return `{:ok, event}` or `:error`.
  - `all_events(store_pid)` — return all stored events as a list.
- `WebhookReceiver.MemoryStore` — a GenServer implementing `WebhookReceiver.Store` using an in-memory map.
  - Expose `start_link/1` accepting an options list.
  - Each stored event is a map with at least `:event_id`, `:payload` (the decoded map, with string keys), and `:status` (always `:pending` on creation).

**Router behavior**

- Read the raw request body and the `stripe-signature` header.
- If the signature header is missing, empty, or verification fails, return 401 with JSON body `{"error": "invalid_signature"}`.
- If verification passes, decode the JSON body, extract the `"id"` field as the event ID.
- If the event ID has already been stored, return 200 with `{"status": "duplicate"}`.
- If new, store it and return 200 with `{"status": "received"}`.
- If the JSON body is malformed or missing an `"id"` field, return 400 with `{"error": "bad_payload"}`.
- Any request not matching `POST /api/webhooks/stripe` (different path, or different method on that path) returns 404 with a plain-text body.

**Raw body handling**

- The raw body must be read and kept available for both signature verification and JSON decoding.
- Use a custom body reader or cache the raw body in the conn's assigns.

**Dependencies**

- Use only Plug and Jason (plus `:crypto` from OTP). No Phoenix, no Ecto, no database drivers.

**Interface contract**

- The `:store` option's value is the **pid** of an already-started store process, not a module name. Callers do `{:ok, store} = WebhookReceiver.MemoryStore.start_link([])`, then invoke the router directly via `WebhookReceiver.Router.init(secret: secret, store: store)` followed by `WebhookReceiver.Router.call(conn, init_result)`.
- `init/1` must therefore carry the options through to `call/2` (e.g. `use Plug.Router, copy_opts_to_assign: :webhook_opts`), and the router passes that pid as the first argument of every `WebhookReceiver.Store` call.
- `WebhookReceiver.Store` is not just a behaviour definition: it must ALSO define public client functions with the same names and arities as its callbacks, each dispatching to the given store process (e.g. via `GenServer.call(store, ...)`), so callers can invoke e.g. `WebhookReceiver.Store.get_event(store, event_id)` directly on the module.
