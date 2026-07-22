defmodule Notifications do
  @moduledoc """
  Pub/sub for per-user notifications, backed by a `Registry` in `:duplicate` mode.

  A process subscribes to a `user_id` with `subscribe/2`. Any payload published for
  that `user_id` via `publish/3` is delivered to every subscriber as a plain message:

      {:notification, payload}

  Only OTP primitives are used — no external pub/sub dependency.

  ## Example

      {:ok, _pid} = Notifications.start_link([])
      :ok = Notifications.subscribe("user-1")
      :ok = Notifications.publish("user-1", %{"kind" => "mention"})

      receive do
        {:notification, payload} -> payload
      end

  """

  @default_name Notifications

  @doc """
  Starts the registry backing the notification pub/sub.

  ## Options

    * `:name` — the name the backing `Registry` is registered under. Defaults to
      `Notifications`. The same name must then be passed to `subscribe/2` and
      `publish/3` (both default to `Notifications`).

  Returns `{:ok, pid}` on success, or `{:error, {:already_started, pid}}` if a process
  is already registered under that name.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, @default_name)
    Registry.start_link(keys: :duplicate, name: name, partitions: System.schedulers_online())
  end

  @doc """
  Returns a child specification so `Notifications` can be placed in a supervision tree.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :name, @default_name),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  Every payload published for `user_id` is then delivered to the caller's mailbox as
  `{:notification, payload}`. Subscriptions are automatically removed when the calling
  process terminates. Always returns `:ok`.
  """
  @spec subscribe(atom() | pid(), term()) :: :ok
  def subscribe(server \\ @default_name, user_id) do
    {:ok, _owner} = Registry.register(server, key(user_id), nil)
    :ok
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.

  Each subscriber receives `{:notification, payload}`. Publishing to a `user_id` with no
  subscribers is a no-op. Always returns `:ok`.
  """
  @spec publish(atom() | pid(), term(), term()) :: :ok
  def publish(server \\ @default_name, user_id, payload) do
    Registry.dispatch(server, key(user_id), fn subscribers ->
      Enum.each(subscribers, fn {pid, _value} -> send(pid, {:notification, payload}) end)
    end)
  end

  @spec key(term()) :: term()
  defp key(user_id), do: {:user, user_id}
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing a *coalescing* long-polling notifications endpoint.

  Unlike a plain long poll — which returns as soon as the first notification arrives —
  this plug returns a whole burst:

    1. It subscribes the request process to `Notifications` for `conn.assigns.user_id`.
    2. It blocks in a `receive` for at most `:timeout_ms` waiting for the *first*
       notification. If nothing arrives, it responds `204 No Content` with an empty body.
    3. Once the first notification arrives it opens a *linger* window: it keeps draining
       `{:notification, payload}` messages with a `receive` whose `after` is `:linger_ms`,
       accumulating payloads (in arrival order) until a full `:linger_ms` passes with no
       new message.
    4. It responds `200 OK`, `content-type: application/json`, with a body of the shape
       `{"notifications": [payload, ...], "count": n}`.

  There is no maximum batch size — the linger window is purely about coalescing a burst.
  A lone notification is still returned as a one-element batch.

  If `conn.assigns.user_id` is absent, the plug responds `401` with body `"unauthorized"`.

  The wait is a genuine blocking `receive` — the connection is truly held open, and no
  `Process.sleep/1` polling loop is involved.

  ## Options

    * `:notifications_server` — name/pid of the `Notifications` registry.
      Defaults to `Notifications`.
    * `:timeout_ms` — maximum time, in milliseconds, to wait for the first notification.
      Defaults to `30_000`.
    * `:linger_ms` — how long, in milliseconds, to keep draining further notifications
      after the first one arrives. Defaults to `50`.

  ## Example

      plug NotificationPoller, timeout_ms: 25_000, linger_ms: 100

  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000
  @default_linger_ms 50

  @typedoc "Validated options carried from `init/1` to `call/2`."
  @type opts :: %{
          notifications_server: atom() | pid(),
          timeout_ms: timeout(),
          linger_ms: non_neg_integer()
        }

  @doc """
  Validates and normalises the plug options into the map handed to `call/2`.

  See the module documentation for the supported options.
  """
  @impl Plug
  @spec init(keyword()) :: opts()
  def init(opts) when is_list(opts) do
    %{
      notifications_server: Keyword.get(opts, :notifications_server, Notifications),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
      linger_ms: Keyword.get(opts, :linger_ms, @default_linger_ms)
    }
  end

  @doc """
  Handles `GET /api/notifications/poll`.

  Responds with `401` when `conn.assigns.user_id` is missing, `204` when the poll times
  out with no notifications, and otherwise `200` with the JSON-encoded batch of every
  payload collected during the burst.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, %{} = opts) do
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

  @spec poll(Plug.Conn.t(), term(), opts()) :: Plug.Conn.t()
  defp poll(conn, user_id, opts) do
    :ok = Notifications.subscribe(opts.notifications_server, user_id)

    case await_first(opts.timeout_ms) do
      :timeout ->
        conn
        |> send_resp(204, "")
        |> halt()

      {:ok, payload} ->
        payloads = drain([payload], opts.linger_ms)
        body = Jason.encode!(%{"notifications" => payloads, "count" => length(payloads)})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, body)
        |> halt()
    end
  end

  # Blocks — genuinely, not by sleeping — until the first notification arrives or the
  # overall poll timeout elapses.
  @spec await_first(timeout()) :: {:ok, term()} | :timeout
  defp await_first(timeout_ms) do
    receive do
      {:notification, payload} -> {:ok, payload}
    after
      timeout_ms -> :timeout
    end
  end

  # The linger window: keep collecting notifications until `linger_ms` passes with none.
  # `acc` is kept in reverse arrival order and reversed on the way out.
  @spec drain([term()], non_neg_integer()) :: [term()]
  defp drain(acc, linger_ms) do
    receive do
      {:notification, payload} -> drain([payload | acc], linger_ms)
    after
      linger_ms -> Enum.reverse(acc)
    end
  end
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the coalescing long-poll endpoint.

  Routes:

    * `GET /api/notifications/poll` — forwarded to `NotificationPoller`.
    * anything else — `404 Not Found`.

  It accepts the same options as `NotificationPoller` (`:notifications_server`,
  `:timeout_ms` and `:linger_ms`) and passes them straight through.

  ## Example

      Plug.Cowboy.http(NotificationRouter, notifications_server: Notifications, linger_ms: 100)

  """

  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Initialises the router, normalising the poller options once at compile/startup time.

  The returned value is threaded back into `call/2` as the router's options.
  """
  @spec init(keyword()) :: NotificationPoller.opts()
  def init(opts) when is_list(opts) do
    NotificationPoller.init(opts)
  end

  @doc """
  Matches and dispatches the request, making the poller options available to the routes.
  """
  @spec call(Plug.Conn.t(), NotificationPoller.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, %{} = opts) do
    conn
    |> put_private(:notification_poller_opts, opts)
    |> super(opts)
  end

  get "/api/notifications/poll" do
    NotificationPoller.call(conn, conn.private.notification_poller_opts)
  end

  match _ do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "not found")
    |> halt()
  end
end