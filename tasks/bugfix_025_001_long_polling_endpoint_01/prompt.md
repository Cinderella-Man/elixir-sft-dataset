# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

## The buggy module

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
    {:error, _pid} = Registry.register(server, user_id, nil)
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

## Failing test report

```
8 of 11 test(s) failed:

  * test returns a notification published mid-poll
      {:EXIT, #PID<0.213.0>}: {%Plug.Conn.WrapperError{conn: %Plug.Conn{adapter: {Plug.Adapters.Test.Conn, :...}, assigns: %{user_id: "user:1", poller_opts: [notifications_server: :notifications_1092, timeout_ms: 500]}, body_params: %Plug.Conn.Unfetched{aspect: :body_params}, cookies: %Plug.Conn.Unfetched{aspect: :cookies}, halted: false, host: "www.example.com", method: "GET", owner: nil, params: %{}, path_info: ["api", "notifications", "poll"], path_params: %{}, port: 80, private: %{plug_route: {"/a

  * test returns 204 when timeout expires with no notifications
      ** (MatchError) no match of right hand side value:
      
          {:ok, #PID<0.221.0>}
      

  * test user A notification not delivered to user B
      {:EXIT, #PID<0.226.0>}: {%Plug.Conn.WrapperError{conn: %Plug.Conn{adapter: {Plug.Adapters.Test.Conn, :...}, assigns: %{user_id: "user:b", poller_opts: [notifications_server: :notifications_1412, timeout_ms: 500]}, body_params: %Plug.Conn.Unfetched{aspect: :body_params}, cookies: %Plug.Conn.Unfetched{aspect: :cookies}, halted: false, host: "www.example.com", method: "GET", owner: nil, params: %{}, path_info: ["api", "notifications", "poll"], path_params: %{}, port: 80, private: %{plug_route: {"/a

  * test delivers to the correct user among many pollers
      {:EXIT, #PID<0.231.0>}: {%Plug.Conn.WrapperError{conn: %Plug.Conn{adapter: {Plug.Adapters.Test.Conn, :...}, assigns: %{user_id: "user:b", poller_opts: [notifications_server: :notifications_1540, timeout_ms: 500]}, body_params: %Plug.Conn.Unfetched{aspect: :body_params}, cookies: %Plug.Conn.Unfetched{aspect: :cookies}, halted: false, host: "www.example.com", method: "GET", owner: nil, params: %{}, path_info: ["api", "notifications", "poll"], path_params: %{}, port: 80, private: %{plug_route: {"/a

  (…4 more)
```
