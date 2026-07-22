Write me a set of Elixir modules that implement a **cursor-resumable, gap-free** long-polling notifications endpoint. Unlike a naive long poll (which silently drops any notification published in the window between two polls), this variant hands every response a monotonic **cursor** and keeps a short per-user replay buffer, so a client that echoes its last cursor back never misses an event — even one published while it was not connected.

## 1. `Notifications` module

This module manages sequenced pub/sub for user notifications. Back it with a `GenServer` (do **not** use `Registry`, since we must assign sequence numbers and retain recent history). It should provide:

- `Notifications.start_link(opts)` — starts the backing process. Accept a `:name` option for registration (default `Notifications`) and a `:buffer_size` option (max retained events per user, default `100`).

- `Notifications.subscribe(server \\ Notifications, user_id)` — subscribes the calling process to notifications for `user_id`. When an event is published, the subscribing process receives `{:notification, seq, payload}` where `seq` is the event's assigned sequence number. Returns `:ok`. The server must monitor subscribers and drop them on exit.

- `Notifications.publish(server \\ Notifications, user_id, payload)` — assigns the next per-user sequence number (starting at 1), appends `{seq, payload}` to that user's replay buffer (evicting oldest beyond `:buffer_size`), delivers `{:notification, seq, payload}` to all current subscribers, and returns `{:ok, seq}`.

- `Notifications.events_since(server \\ Notifications, user_id, cursor)` — returns the buffered `{seq, payload}` tuples for `user_id` whose `seq` is strictly greater than `cursor`, **oldest first**.

Use only OTP primitives (`GenServer`, `Process`). No Phoenix.PubSub, no external deps.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` for `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option and a `:timeout_ms` option (default `30_000`).

- Extract the user ID from `conn.assigns.user_id`. If missing, return 401 with body `"unauthorized"`.

- Read a `since` query parameter (an integer cursor; default `0`, and any missing/negative/garbage value is treated as `0`).

- **Subscribe first, then check the buffer** (this ordering is what closes the gap): after subscribing, call `events_since(server, user_id, since)`.
  - If the buffer already has newer events, respond immediately (do not block).
  - Otherwise, block on a `receive` with `after` waiting for a `{:notification, seq, payload}` message.

- A 200 response has `content-type: application/json`, a header `x-notification-cursor` set to the highest returned sequence number, and a JSON body of the shape `{"cursor": <max_seq>, "events": [<payload>, ...]}`. When answering from the buffer, include every newer event in order; when answering from a live message, include just that one event.

- On timeout, return 204 No Content with an empty body and an `x-notification-cursor` header echoing the request's `since` cursor (so the client resumes from where it was).

Use `Jason` for JSON encoding.

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`, passing through `:notifications_server` and `:timeout_ms`.
- Returns 404 for anything else.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a blocking `receive`), not a polling loop with `Process.sleep`.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.