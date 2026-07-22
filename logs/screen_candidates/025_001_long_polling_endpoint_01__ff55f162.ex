defmodule Notifications do
  @moduledoc """
  Pub/sub for per-user notifications, built on OTP primitives only.

  The backing store is a `Registry` started in `:duplicate` mode: every subscriber registers
  itself under a key derived from the `user_id` it cares about, and `publish/3` dispatches a
  `{:notification, payload}` message to every process registered under that key.

  Because a `Registry` automatically removes entries for processes that die, subscribers never
  need to clean up after a crash. `unsubscribe/2` is provided for long-lived processes (such as
  a web server's connection process that is reused across keep-alive requests) that want to stop
  receiving messages while staying alive.

  ## Example

      children = [
        {Notifications, name: Notifications}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      :ok = Notifications.subscribe(Notifications, "user-1")
      :ok = Notifications.publish(Notifications, "user-1", %{"kind" => "ping"})

      receive do
        {:notification, payload} -> payload
      end
  """

  @typedoc "Name or pid of the registry backing a `Notifications` instance."
  @type server :: atom() | pid()

  @typedoc "Identifier of the user a notification belongs to."
  @type user_id :: term()

  @doc """
  Builds the child specification used when `Notifications` is placed under a supervisor.

  Accepts the same options as `start_link/1`.
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
  Starts the process backing the pub/sub system.

  ## Options

    * `:name` - the name the backing `Registry` is registered under. Defaults to `Notifications`.
    * `:partitions` - number of registry partitions. Defaults to `System.schedulers_online/0`.

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    partitions = Keyword.get(opts, :partitions, System.schedulers_online())

    Registry.start_link(keys: :duplicate, name: name, partitions: partitions)
  end

  @doc """
  Subscribes the calling process to notifications published for `user_id`.

  Every subsequent `publish/3` for the same `user_id` sends `{:notification, payload}` to the
  caller. The subscription is removed automatically when the caller terminates.
  """
  @spec subscribe(server(), user_id()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _owner} = Registry.register(server, key(user_id), :subscriber)
    :ok
  end

  @doc """
  Removes every subscription the calling process holds for `user_id`.

  Safe to call even when the caller is not subscribed.
  """
  @spec unsubscribe(server(), user_id()) :: :ok
  def unsubscribe(server \\ __MODULE__, user_id) do
    Registry.unregister(server, key(user_id))
    :ok
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.

  Each subscriber receives the message `{:notification, payload}`. Always returns `:ok`, even
  when there are no subscribers.
  """
  @spec publish(server(), user_id(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, payload) do
    message = {:notification, payload}

    Registry.dispatch(server, key(user_id), fn entries ->
      Enum.each(entries, fn {pid, _value} -> send(pid, message) end)
    end)

    :ok
  end

  @spec key(user_id()) :: {:user, user_id()}
  defp key(user_id), do: {:user, user_id}
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing the long-polling endpoint `GET /api/notifications/poll`.

  The plug subscribes the request process to `Notifications` for `conn.assigns.user_id` and then
  genuinely blocks in a `receive` until either a notification arrives or the configured timeout
  elapses. No busy-waiting or `Process.sleep/1` loop is involved.

  ## Responses

    * `401` with body `"unauthorized"` when `conn.assigns.user_id` is missing.
    * `200` with `content-type: application/json` and the JSON-encoded payload when a
      notification arrives before the timeout.
    * `204` with an empty body when the timeout expires first.

  ## Options

    * `:notifications_server` - name or pid of the `Notifications` process. Defaults to
      `Notifications`.
    * `:timeout_ms` - how long the connection is held open, in milliseconds. Defaults to
      `30_000`.

  ## Example

      plug NotificationPoller, notifications_server: Notifications, timeout_ms: 25_000
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000

  @typedoc "Normalized options as returned by `init/1`."
  @type opts :: %{
          required(:notifications_server) => Notifications.server(),
          required(:timeout_ms) => timeout()
        }

  @doc """
  Normalizes the plug options into the map used by `call/2`.

  See the module documentation for the supported options.
  """
  @impl Plug
  @spec init(keyword() | opts()) :: opts()
  def init(opts) when is_map(opts) do
    %{
      notifications_server: Map.get(opts, :notifications_server, Notifications),
      timeout_ms: Map.get(opts, :timeout_ms, @default_timeout_ms)
    }
  end

  def init(opts) when is_list(opts) do
    %{
      notifications_server: Keyword.get(opts, :notifications_server, Notifications),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    }
  end

  @doc """
  Handles a long-poll request.

  Responds with `401` when the connection carries no `:user_id` assign, otherwise blocks up to
  `:timeout_ms` waiting for a `{:notification, payload}` message and answers with `200` (payload
  as JSON) or `204` (nothing arrived in time).
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword() | opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, opts) when is_list(opts), do: call(conn, init(opts))

  def call(%Plug.Conn{} = conn, %{notifications_server: server, timeout_ms: timeout_ms}) do
    case Map.get(conn.assigns, :user_id) do
      nil -> unauthorized(conn)
      user_id -> long_poll(conn, server, user_id, timeout_ms)
    end
  end

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "unauthorized")
    |> halt()
  end

  @spec long_poll(Plug.Conn.t(), Notifications.server(), Notifications.user_id(), timeout()) ::
          Plug.Conn.t()
  defp long_poll(conn, server, user_id, timeout_ms) do
    :ok = Notifications.subscribe(server, user_id)

    try do
      receive do
        {:notification, payload} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(payload))
          |> halt()
      after
        timeout_ms ->
          conn
          |> send_resp(204, "")
          |> halt()
      end
    after
      Notifications.unsubscribe(server, user_id)
    end
  end
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the long-polling notifications endpoint.

  `GET /api/notifications/poll` is handed to `NotificationPoller`; every other request gets a
  `404`. The options given to the router are forwarded verbatim to the poller.

  ## Options

    * `:notifications_server` - name or pid of the `Notifications` process. Defaults to
      `Notifications`.
    * `:timeout_ms` - how long the connection is held open, in milliseconds. Defaults to
      `30_000`.

  ## Example

      Plug.Cowboy.http(NotificationRouter, notifications_server: Notifications, timeout_ms: 30_000)
  """

  use Plug.Router

  @private_opts :notification_router_opts

  plug :match
  plug :dispatch

  @doc """
  Keeps the router options as given so they can be handed to `NotificationPoller` at runtime.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Stores the router options on the connection and runs the `match`/`dispatch` pipeline.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, opts) do
    conn
    |> put_private(@private_opts, opts)
    |> super(opts)
  end

  get "/api/notifications/poll" do
    poller_opts =
      conn.private
      |> Map.get(@private_opts, [])
      |> NotificationPoller.init()

    NotificationPoller.call(conn, poller_opts)
  end

  match _ do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "not found")
  end
end