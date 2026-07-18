Write me a set of Elixir modules that implement a **multi-channel fan-in long-polling notifications endpoint**. Instead of one stream per user, each client subscribes to several named channels at once and the long-poll returns the first notification that arrives on **any** of them, tagged with which channel it came from. I need three pieces:

## 1. `Notifications` module

This module manages per-`(user_id, channel)` pub/sub. It should provide:

- `Notifications.start_link(opts)` — starts whatever backing process is needed. Accept a `:name` option for registration (default `Notifications`). The module must also be startable under a supervisor via the `{Notifications, name: ...}` child-spec form (i.e. provide a `child_spec/1`), since the tests bring it up with `start_supervised!({Notifications, name: server})`.

- `Notifications.subscribe(server \\ Notifications, user_id, channel)` — subscribes the calling process to a single `(user_id, channel)` pair. When a notification is published to that pair, the subscribing process should receive a message `{:notification, channel, payload}`. Returns `:ok`.

- `Notifications.publish(server \\ Notifications, user_id, channel, payload)` — publishes `payload` to all processes subscribed to `(user_id, channel)`. Returns `:ok` (including when there are no subscribers).

Use only OTP primitives (e.g., `Registry`, `GenServer`, `Process`). Do not pull in Phoenix.PubSub or any external dependencies. A `Registry` in `:duplicate` mode keyed on `{user_id, channel}` is a fine backing store.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` that implements `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option and a `:timeout_ms` option (max time to hold the connection open, default `30_000`).

- Extract the user ID from the connection assigns at `conn.assigns.user_id`. If `user_id` is missing, return 401 with body `"unauthorized"`.

- Read the requested channels from the `channels` query parameter — a comma-separated list (e.g. `?channels=orders,alerts,dm`). If the parameter is absent or resolves to an empty list, return 400 with body `"no channels"`.

- Subscribe to `(user_id, channel)` for **each** requested channel, then block (using a single `receive` with `after`) waiting for the first `{:notification, channel, payload}` message from any of them.

- If a notification arrives within the timeout, return 200 with `content-type: application/json` and a JSON body of the shape `{"channel": channel, "payload": payload}` identifying which channel fired.

- If the timeout expires with no notification, return 204 No Content with an empty body.

Use `Jason` for JSON encoding (the only external dependency allowed).

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`.
- Returns 404 for anything else.
- Accepts the same `:notifications_server` and `:timeout_ms` options and passes them through to the poller.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a single blocking `receive` across all channels), not a polling loop with `Process.sleep`.
- Only the first notification (on whichever channel) is returned; the rest can stay in the mailbox.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.
