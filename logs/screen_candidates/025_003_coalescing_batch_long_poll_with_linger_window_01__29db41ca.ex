defmodule Notifications do
  @moduledoc """
  Pub/sub for per-user notifications built on a `Registry` in `:duplicate` mode.

  Processes call `subscribe/2` to register interest in a `user_id`. Any payload
  published for that `user_id` via `publish/3` is delivered to every subscriber
  as a `{:notification, payload}` message.

  Only OTP primitives are used — no external pub/sub dependency.
  """

  @default_name __MODULE__

  @doc """
  Returns a child specification so the module can be started as
  `{Notifications, opts}` under a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, @default_name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts the backing registry.

  Options:

    * `:name` — the name the registry is registered under (default `Notifications`).
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    Registry.start_link(keys: :duplicate, name: name, partitions: 1)
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  The caller will receive `{:notification, payload}` messages for every payload
  published to `user_id` while the subscription is alive.
  """
  @spec subscribe(atom() | pid(), term()) :: {:ok, pid()} | {:error, term()}
  def subscribe(server \\ @default_name, user_id) do
    Registry.register(server, key(user_id), nil)
  end

  @doc """
  Publishes `payload` to every process subscribed to `user_id`.

  Always returns `:ok`, including when there are no subscribers.
  """
  @spec publish(atom() | pid(), term(), term()) :: :ok
  def publish(server \\ @default_name, user_id, payload) do
    Registry.dispatch(server, key(user_id), fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)

    :ok
  end

  @spec key(term()) :: term()
  defp key(user_id), do: user_id
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing a coalescing (batching) long-poll endpoint for
  `GET /api/notifications/poll`.

  The plug subscribes the request process to `Notifications` for the connection's
  `conn.assigns.user_id` and blocks on a `receive` until the first notification
  arrives or `:timeout_ms` elapses. Once the first notification arrives, a linger
  window of `:linger_ms` is opened and every further notification is drained,
  resetting the window each time. All collected payloads are returned in arrival
  order as a single JSON batch.

  Responses:

    * `200` — `{"notifications": [payload, ...], "count": n}` with
      `content-type: application/json`
    * `204` — no notification arrived before `:timeout_ms`
    * `401` — body `"unauthorized"` when `conn.assigns.user_id` is missing
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000
  @default_linger_ms 50

  @doc """
  Normalizes the plug options.

  Recognized keys: `:notifications_server`, `:timeout_ms`, `:linger_ms`.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    [
      notifications_server: Keyword.get(opts, :notifications_server, Notifications),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
      linger_ms: Keyword.get(opts, :linger_ms, @default_linger_ms)
    ]
  end

  @doc """
  Handles the long-poll request, holding the connection open until a batch of
  notifications is available or the timeout expires.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case Map.get(conn.assigns, :user_id) do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(401, "unauthorized")
        |> halt()

      user_id ->
        poll(conn, user_id, opts)
    end
  end

  @spec poll(Plug.Conn.t(), term(), keyword()) :: Plug.Conn.t()
  defp poll(conn, user_id, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)
    linger_ms = Keyword.fetch!(opts, :linger_ms)

    Notifications.subscribe(server, user_id)

    receive do
      {:notification, payload} ->
        payloads = drain([payload], linger_ms)
        respond(conn, payloads)
    after
      timeout_ms ->
        conn
        |> send_resp(204, "")
        |> halt()
    end
  end

  @spec drain([term()], non_neg_integer()) :: [term()]
  defp drain(acc, linger_ms) do
    receive do
      {:notification, payload} -> drain([payload | acc], linger_ms)
    after
      linger_ms -> Enum.reverse(acc)
    end
  end

  @spec respond(Plug.Conn.t(), [term()]) :: Plug.Conn.t()
  defp respond(conn, payloads) do
    body = Jason.encode!(%{"notifications" => payloads, "count" => length(payloads)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
    |> halt()
  end
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the coalescing long-poll endpoint.

  Routes `GET /api/notifications/poll` to `NotificationPoller` and returns `404`
  for every other request. The `:notifications_server`, `:timeout_ms` and
  `:linger_ms` options are passed straight through to the poller.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Normalizes router options, forwarding them to `NotificationPoller.init/1`.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: NotificationPoller.init(opts)

  @doc """
  Dispatches the request through the `:match` / `:dispatch` pipeline, making the
  normalized options available to the matched route.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:notification_router_opts, opts)
    |> super(opts)
  end

  get "/api/notifications/poll" do
    opts = Map.get(conn.private, :notification_router_opts, NotificationPoller.init([]))
    NotificationPoller.call(conn, opts)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end