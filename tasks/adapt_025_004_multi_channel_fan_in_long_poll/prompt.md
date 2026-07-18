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
