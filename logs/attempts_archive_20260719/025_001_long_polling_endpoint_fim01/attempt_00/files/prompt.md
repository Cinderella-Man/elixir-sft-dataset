# Implement `wait_for_notification/2`

You are completing the `NotificationPoller` Plug, which implements a true
long-polling endpoint. The public `call/2` function has already subscribed the
authenticated process to the `Notifications` pub/sub for the current user and
now delegates the blocking wait to the private helper `wait_for_notification/2`.

Implement the private `wait_for_notification/2` function. It receives the current
`conn` and a `timeout` (in milliseconds). It must block on a `receive` waiting
for a `{:notification, payload}` message — this is genuine long-polling, not a
sleep/poll loop.

- If a `{:notification, payload}` message arrives before `timeout` elapses,
  respond with HTTP 200, set the `content-type` response header to
  `application/json`, and use the JSON-encoded `payload` (via `Jason.encode!/1`)
  as the response body.
- If no notification arrives within `timeout` milliseconds, respond with HTTP
  204 and an empty body.

In both cases return the resulting `conn` (i.e. the value produced by
`send_resp/3`).

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
    # TODO
  end
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` that forwards `GET /api/notifications/poll` to
  `NotificationPoller`, passing through the `:notifications_server` and
  `:timeout_ms` options, and returns 404 for everything else.
  """

  use Plug.Router, copy_opts_to_assign: :poller_opts

  plug :match
  plug :dispatch

  get "/api/notifications/poll" do
    opts = conn.assigns.poller_opts
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
```