# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

Write me a set of Elixir modules that implement a **coalescing (batching) long-polling notifications endpoint**. Unlike a plain long-poll that returns the single first notification, this one waits for the first notification and then keeps the connection open for a short "linger" window to gather any additional notifications that arrive in that burst, returning them all in one batched response. I need three pieces:

## 1. `Notifications` module

This module manages pub/sub for user notifications. It should provide:

- `Notifications.start_link(opts)` — starts whatever backing process is needed. Accept a `:name` option for registration (default `Notifications`). The module must also be startable under a supervisor as `{Notifications, opts}` (e.g. via `start_supervised!({Notifications, name: server})` and `start_supervised!({Notifications, []})`), so provide a `child_spec/1` if your backing process does not already supply one.

- `Notifications.subscribe(server \\ Notifications, user_id)` — subscribes the calling process to notifications for the given `user_id`. When a notification is published for that user, the subscribing process should receive a message `{:notification, payload}`.

- `Notifications.publish(server \\ Notifications, user_id, payload)` — publishes `payload` to all processes currently subscribed to `user_id`. Returns `:ok`, including when there are no subscribers.

Use only OTP primitives (e.g., `Registry`, `GenServer`, `Process`). Do not pull in Phoenix.PubSub or any external dependencies. A `Registry` in `:duplicate` mode is a fine backing store, and it lets multiple processes subscribe to the same `user_id` and each receive the full burst.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` that implements `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option, a `:timeout_ms` option (max time to wait for the FIRST notification, default `30_000`), and a `:linger_ms` option (how long to keep draining additional notifications after the first arrives, default `50`).

- Extract the user ID from the connection assigns at `conn.assigns.user_id`. If `user_id` is missing, return 401 with body exactly `"unauthorized"`.

- Subscribe to `Notifications` for that user, then block (using a `receive` with `after`) waiting for the first `{:notification, payload}` message.

- Once the first notification arrives, open a linger window: keep draining `{:notification, payload}` messages with a `receive` whose `after` is `:linger_ms`, accumulating payloads until a full `:linger_ms` elapses with no further message. Each new message resets the window, so a burst whose gaps are each shorter than `:linger_ms` is collected in full even if its total span runs past the original `:timeout_ms`. Preserve arrival order.

- Return 200 with `content-type: application/json` and a JSON body of the shape `{"notifications": [payload, ...], "count": n}`, where the array contains **every** payload collected during the burst in arrival order and `count` is the number of payloads.

- If the `:timeout_ms` expires before any notification arrives, return 204 No Content with an empty body (`""`).

Use `Jason` for JSON encoding (the only external dependency allowed).

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`.
- Returns 404 for anything else.
- Accepts the same `:notifications_server`, `:timeout_ms`, and `:linger_ms` options and passes them through to the poller.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a blocking `receive`), not a polling loop with `Process.sleep`.
- A single notification must still be returned as a one-element batch; the linger window is about coalescing bursts, not a maximum batch size.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.
