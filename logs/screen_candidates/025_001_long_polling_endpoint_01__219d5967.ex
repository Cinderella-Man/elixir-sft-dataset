defmodule Notifications do
  @moduledoc """
  Pub/sub for per-user notifications, backed by a `Registry` in `:duplicate` mode.

  Processes call `subscribe/2` to register interest in a `user_id`. When another
  process calls `publish/3` for that `user_id`, every subscriber receives a
  `{:notification, payload}` message in its mailbox.

  Only OTP primitives are used — no external pub/sub library is required.

      iex> {:ok, _pid} = Notifications.start_link(name: MyNotifications)
      iex> :ok = Notifications.subscribe(MyNotifications, "user-1")
      iex> :ok = Notifications.publish(MyNotifications, "user-1", %{"kind" => "ping"})
      iex> receive do
      ...>   {:notification, payload} -> payload
      ...> after
      ...>   1_000 -> :timeout
      ...> end
      %{"kind" => "ping"}

  Subscriptions are automatically removed when the subscribing process exits,
  because `Registry` monitors its entries.
  """

  @type server :: atom() | pid()
  @type user_id :: term()

  @doc """
  Returns a child specification so `Notifications` can be placed in a supervision tree.

  Accepts the same options as `start_link/1`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts the backing registry process.

  ## Options

    * `:name` - the name under which the registry is registered. Defaults to
      `Notifications`. Pass the same value to `subscribe/2` and `publish/3`.

  Any other options are forwarded to `Registry.start_link/1`, except `:keys`
  and `:name`, which are always controlled by this module.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    opts
    |> Keyword.drop([:name, :keys])
    |> Keyword.merge(keys: :duplicate, name: name)
    |> Registry.start_link()
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  Published payloads arrive as `{:notification, payload}` messages. Calling this
  more than once for the same `user_id` from the same process results in
  duplicate deliveries, one per subscription.
  """
  @spec subscribe(server(), user_id()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _owner} = Registry.register(server, user_id, nil)
    :ok
  end

  @doc """
  Unsubscribes the calling process from all of its subscriptions for `user_id`.

  It is not an error to unsubscribe when no subscription exists.
  """
  @spec unsubscribe(server(), user_id()) :: :ok
  def unsubscribe(server \\ __MODULE__, user_id) do
    Registry.unregister(server, user_id)
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.

  Delivery is asynchronous and best-effort: this function returns `:ok` even when
  there are no subscribers.
  """
  @spec publish(server(), user_id(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, payload) do
    Registry.dispatch(server, user_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing a long-polling notifications endpoint.

  The plug subscribes the request process to `Notifications` for
  `conn.assigns.user_id` and then blocks in a `receive` until either a
  notification arrives or the configured timeout expires.

  Responses:

    * `200` with `content-type: application/json` and the JSON-encoded payload,
      when a notification arrives in time;
    * `204` with an empty body, when the timeout expires first;
    * `401` with body `"unauthorized"`, when `conn.assigns.user_id` is missing.

  ## Options

    * `:notifications_server` - name or pid of the `Notifications` process.
      Defaults to `Notifications`.
    * `:timeout_ms` - maximum time, in milliseconds, to hold the connection
      open. Defaults to `30_000`.

  ## Example

      plug NotificationPoller, notifications_server: MyNotifications, timeout_ms: 10_000
  """

  @behaviour Plug

  @default_timeout_ms 30_000

  @doc """
  Validates and normalises the plug options at compile time.

  See the moduledoc for the supported options.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    server = Keyword.get(opts, :notifications_server, Notifications)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    unless is_integer(timeout_ms) and timeout_ms >= 0 do
      raise ArgumentError, ":timeout_ms must be a non-negative integer, got: #{inspect(timeout_ms)}"
    end

    [notifications_server: server, timeout_ms: timeout_ms]
  end

  @doc """
  Handles the long-poll request, holding the connection open until a
  notification arrives or the timeout expires.

  The response is always sent, and the returned connection is halted.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case Map.get(conn.assigns, :user_id) do
      nil -> unauthorized(conn)
      user_id -> poll(conn, user_id, opts)
    end
  end

  @spec poll(Plug.Conn.t(), Notifications.user_id(), keyword()) :: Plug.Conn.t()
  defp poll(conn, user_id, opts) do
    server = Keyword.get(opts, :notifications_server, Notifications)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    :ok = Notifications.subscribe(server, user_id)

    try do
      receive do
        {:notification, payload} -> send_payload(conn, payload)
      after
        timeout_ms -> send_no_content(conn)
      end
    after
      Notifications.unsubscribe(server, user_id)
    end
  end

  @spec send_payload(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp send_payload(conn, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(payload))
    |> Plug.Conn.halt()
  end

  @spec send_no_content(Plug.Conn.t()) :: Plug.Conn.t()
  defp send_no_content(conn) do
    conn
    |> Plug.Conn.send_resp(204, "")
    |> Plug.Conn.halt()
  end

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(401, "unauthorized")
    |> Plug.Conn.halt()
  end
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the long-polling notifications endpoint.

  Routes:

    * `GET /api/notifications/poll` - handled by `NotificationPoller`;
    * anything else - `404` with body `"not found"`.

  The router accepts the same options as `NotificationPoller`
  (`:notifications_server` and `:timeout_ms`) and passes them through.

  ## Example

      Plug.Cowboy.http(NotificationRouter, notifications_server: MyNotifications)
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Stores the router options so they can be forwarded to `NotificationPoller`.

  See the moduledoc for the supported options.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Dispatches the request, making the router options available to matched routes.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:notification_router_opts, opts)
    |> super(opts)
  end

  get "/api/notifications/poll" do
    opts =
      conn.private
      |> Map.get(:notification_router_opts, [])
      |> NotificationPoller.init()

    NotificationPoller.call(conn, opts)
  end

  match _ do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "not found")
    |> halt()
  end
end