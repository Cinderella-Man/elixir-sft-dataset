Implement the public `publish/3` function on the `Notifications` module. It takes a
`server` reference (defaulting to the module name), a `user_id`, and a `payload`. It
should deliver `payload` to every process currently subscribed to `user_id`. Use
`Registry.dispatch/3` against the given `server` for the `user_id` key; in the
dispatch callback you receive the list of registered entries as `{pid, value}` tuples,
and for each one you should `send` that pid a `{:notification, payload}` message. After
dispatching, return `:ok`.

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
    # TODO
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