Write me a set of Elixir modules that implement a long-polling notifications endpoint. I need three pieces:

## 1. `Notifications` module

This module manages pub/sub for user notifications. It should provide:

- `Notifications.start_link(opts)` — starts whatever backing process is needed. Accept a `:name` option for registration (default `Notifications`).

- `Notifications.subscribe(server \\ Notifications, user_id)` — subscribes the calling process to notifications for the given `user_id`. When a notification is published for that user, the subscribing process should receive a message `{:notification, payload}`.

- `Notifications.publish(server \\ Notifications, user_id, payload)` — publishes `payload` to all processes currently subscribed to `user_id`. Returns `:ok`.

Use only OTP primitives (e.g., `Registry`, `GenServer`, `Process`). Do not pull in Phoenix.PubSub or any external dependencies. A `Registry` in `:duplicate` mode is a fine backing store.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` that implements `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option (the name/pid of the `Notifications` process) and a `:timeout_ms` option (max time to hold the connection open, default `30_000`).

- Extract the user ID from the connection assigns at `conn.assigns.user_id`. If `user_id` is missing, return 401 with body `"unauthorized"`.

- Subscribe to `Notifications` for that user, then block (using a `receive` with `after`) waiting for a `{:notification, payload}` message.

- If a notification arrives within the timeout, return 200 with `content-type: application/json` and the JSON-encoded payload as the body.

- If the timeout expires with no notification, return 204 No Content with an empty body.

Use `Jason` for JSON encoding (the only external dependency allowed).

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`.
- Returns 404 for anything else.

The router should accept the same `:notifications_server` and `:timeout_ms` options and pass them through to the poller.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a blocking `receive`), not a polling loop with `Process.sleep`.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.