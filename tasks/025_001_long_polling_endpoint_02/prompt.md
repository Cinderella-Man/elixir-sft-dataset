Implement the public `call/2` function for the `NotificationPoller` plug. It receives
the `conn` and the plug `opts`. It should fetch the required `:notifications_server`
option using `Keyword.fetch!/2`, and read the `:timeout_ms` option with
`Keyword.get/3`, falling back to the `@default_timeout_ms` module attribute.

Then it must look at `conn.assigns[:user_id]`. If that is `nil`, respond immediately
with status 401 and body `"unauthorized"` using `send_resp/3`. Otherwise, subscribe
the current process to notifications for that `user_id` via
`Notifications.subscribe/2` (passing the configured server), and then hand off to the
private `wait_for_notification/2` helper with the `conn` and the resolved timeout,
returning its result.

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
    # TODO
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