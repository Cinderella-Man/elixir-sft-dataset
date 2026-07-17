defmodule Notifications do
  @moduledoc """
  In-memory pub/sub for user notifications backed by a `Registry` in
  `:duplicate` mode. Subscribers receive `{:notification, payload}` messages.

  The `server` reference may be the registered name of the backing registry or
  the pid returned by `start_link/1` (it is resolved back to its registered
  name, since `Registry` itself only accepts names).
  """

  @type server :: atom() | pid()

  @doc """
  Starts the backing `Registry`. Accepts a `:name` option (default
  `Notifications`) used both for registration and as the server reference.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Registry.start_link(keys: :duplicate, name: name)
  end

  @doc """
  Builds the child specification used when starting this module under a
  supervisor. Accepts the same options as `start_link/1`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  The caller will receive `{:notification, payload}` for every subsequent
  `publish/3` targeting the same `user_id`.
  """
  @spec subscribe(server(), term()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _pid} = Registry.register(resolve(server), user_id, nil)
    :ok
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.

  Publishing to a `user_id` with no subscribers is a no-op.
  """
  @spec publish(server(), term(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, payload) do
    Registry.dispatch(resolve(server), user_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)

    :ok
  end

  @spec resolve(server()) :: atom()
  defp resolve(server) when is_pid(server) do
    case Process.info(server, :registered_name) do
      {:registered_name, name} when is_atom(name) ->
        name

      _other ->
        raise ArgumentError,
              "the notifications registry #{inspect(server)} has no registered name; " <>
                "start it with a `:name` option and pass that name instead"
    end
  end

  defp resolve(server), do: server
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing `GET /api/notifications/poll` using true long-polling: it
  subscribes to `Notifications` for the authenticated user and blocks on a
  `receive` until a notification arrives or the timeout elapses.

  Options:

    * `:notifications_server` (required) — name or pid of the `Notifications`
      process.
    * `:timeout_ms` — how long to hold the connection open (default `30_000`).
  """

  import Plug.Conn

  @default_timeout_ms 30_000

  @doc """
  Plug callback. Returns the options unchanged.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Plug callback. Responds 401 without a `:user_id` assign, 200 with the
  JSON-encoded payload when a notification arrives, or 204 on timeout.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
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
