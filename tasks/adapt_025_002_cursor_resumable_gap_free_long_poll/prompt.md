# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Notifications do
  @moduledoc """
  In-memory pub/sub for user notifications backed by a `Registry` in
  `:duplicate` mode. Subscribers receive `{:notification, payload}` messages.
  """

  @doc """
  Starts the backing `Registry`. Accepts a `:name` option (default
  `Notifications`) used both for registration and as the server reference.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Registry.start_link(keys: :duplicate, name: name)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.
  """
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _pid} = Registry.register(server, user_id, nil)
    :ok
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.
  """
  def publish(server \\ __MODULE__, user_id, payload) do
    Registry.dispatch(server, user_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing `GET /api/notifications/poll` using true long-polling: it
  subscribes to `Notifications` for the authenticated user and blocks on a
  `receive` until a notification arrives or the timeout elapses.
  """

  import Plug.Conn

  @default_timeout_ms 30_000

  def init(opts), do: opts

  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        Notifications.subscribe(server, user_id)
        wait_for_notification(conn, timeout)
    end
  end

  defp wait_for_notification(conn, timeout) do
    receive do
      {:notification, payload} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(payload))
    after
      timeout ->
        send_resp(conn, 204, "")
    end
  end
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` that forwards `GET /api/notifications/poll` to
  `NotificationPoller`, passing through the `:notifications_server` and
  `:timeout_ms` options, and returns 404 for everything else.
  """

  use Plug.Router, copy_opts_to_assign: :poller_opts

  plug(:match)
  plug(:dispatch)

  get "/api/notifications/poll" do
    opts = conn.assigns.poller_opts
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
```

## New specification

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
