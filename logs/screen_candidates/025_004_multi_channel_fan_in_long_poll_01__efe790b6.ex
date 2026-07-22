defmodule Notifications do
  @moduledoc """
  Per-`{user_id, channel}` publish/subscribe built on OTP primitives only.

  A `Registry` in `:duplicate` mode is used as the backing store: every subscriber
  registers itself under the key `{user_id, channel}`, and publishing dispatches a
  `{:notification, channel, payload}` message to each registered process.

  No external pub/sub library is required.
  """

  @type user_id :: term()
  @type channel :: String.t()
  @type server :: atom() | pid() | {:via, module(), term()}

  @doc """
  Starts the backing `Registry` process.

  Options:

    * `:name` - the name the registry is registered under (default `Notifications`).

  Any other options are passed through to `Registry.start_link/1`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    opts
    |> Keyword.put(:keys, :duplicate)
    |> Keyword.put(:name, name)
    |> Registry.start_link()
  end

  @doc """
  Returns a child specification so the notifications registry can sit in a supervision tree.
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
  Subscribes the calling process to notifications for `{user_id, channel}`.

  Once subscribed, the caller receives `{:notification, channel, payload}` messages for
  every payload published to that pair.
  """
  @spec subscribe(server(), user_id(), channel()) :: {:ok, pid()} | {:error, term()}
  def subscribe(server \\ __MODULE__, user_id, channel) do
    Registry.register(server, {user_id, channel}, nil)
  end

  @doc """
  Publishes `payload` to every process subscribed to `{user_id, channel}`.

  Each subscriber receives `{:notification, channel, payload}`. Always returns `:ok`,
  even when there are no subscribers.
  """
  @spec publish(server(), user_id(), channel(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, channel, payload) do
    Registry.dispatch(server, {user_id, channel}, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:notification, channel, payload})
      end
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing `GET /api/notifications/poll` as a multi-channel fan-in long poll.

  The client names several channels via the `channels` query parameter (a comma-separated
  list, e.g. `?channels=orders,alerts,dm`). The plug subscribes the request process to
  `{user_id, channel}` for each of them and then blocks in a single `receive` until the
  first notification arrives on *any* channel, or until the timeout expires.

  Responses:

    * `200` with `{"channel": ..., "payload": ...}` when a notification arrives;
    * `204` with an empty body when the timeout expires first;
    * `400` with `"no channels"` when no channels were requested;
    * `401` with `"unauthorized"` when `conn.assigns.user_id` is absent.
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000

  @doc """
  Initialises the plug options.

  Recognised options:

    * `:notifications_server` - the `Notifications` server (default `Notifications`);
    * `:timeout_ms` - how long to hold the connection open (default `#{@default_timeout_ms}`).
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    [
      notifications_server: Keyword.get(opts, :notifications_server, Notifications),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    ]
  end

  @doc """
  Handles a long-poll request, holding the connection open until a notification or timeout.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    server = Keyword.get(opts, :notifications_server, Notifications)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    with {:ok, user_id} <- fetch_user_id(conn),
         conn = Plug.Conn.fetch_query_params(conn),
         {:ok, channels} <- fetch_channels(conn) do
      Enum.each(channels, &Notifications.subscribe(server, user_id, &1))
      await_notification(conn, channels, timeout_ms)
    else
      {:error, :unauthorized} ->
        send_text(conn, 401, "unauthorized")

      {:error, :no_channels} ->
        conn
        |> Plug.Conn.fetch_query_params()
        |> send_text(400, "no channels")
    end
  end

  @spec fetch_user_id(Plug.Conn.t()) :: {:ok, term()} | {:error, :unauthorized}
  defp fetch_user_id(conn) do
    case Map.get(conn.assigns, :user_id) do
      nil -> {:error, :unauthorized}
      user_id -> {:ok, user_id}
    end
  end

  @spec fetch_channels(Plug.Conn.t()) :: {:ok, [String.t()]} | {:error, :no_channels}
  defp fetch_channels(conn) do
    channels =
      conn.query_params
      |> Map.get("channels", "")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case channels do
      [] -> {:error, :no_channels}
      channels -> {:ok, channels}
    end
  end

  @spec await_notification(Plug.Conn.t(), [String.t()], non_neg_integer()) :: Plug.Conn.t()
  defp await_notification(conn, channels, timeout_ms) do
    receive do
      {:notification, channel, payload} when is_binary(channel) ->
        if channel in channels do
          body = Jason.encode!(%{"channel" => channel, "payload" => payload})

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, body)
        else
          await_notification(conn, channels, timeout_ms)
        end
    after
      timeout_ms ->
        send_resp(conn, 204, "")
    end
  end

  @spec send_text(Plug.Conn.t(), pos_integer(), String.t()) :: Plug.Conn.t()
  defp send_text(conn, status, body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the multi-channel long-polling endpoint.

  `GET /api/notifications/poll` is forwarded to `NotificationPoller`; everything else
  returns `404`. The router accepts the same `:notifications_server` and `:timeout_ms`
  options and passes them through to the poller.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @default_timeout_ms 30_000

  @doc """
  Initialises the router options, normalising the poller options passed through on dispatch.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    [
      notifications_server: Keyword.get(opts, :notifications_server, Notifications),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    ]
  end

  @doc """
  Routes the request, making the router options available to the matched route.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:notification_router_opts, init(opts))
    |> super(opts)
  end

  get "/api/notifications/poll" do
    poller_opts =
      conn.private
      |> Map.get(:notification_router_opts, [])
      |> NotificationPoller.init()

    NotificationPoller.call(conn, poller_opts)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end