defmodule Notifications do
  @moduledoc """
  Pub/sub for per-user notifications, built on a `Registry` in `:duplicate` mode.

  Processes call `subscribe/2` to register interest in a user's notifications and
  then receive `{:notification, payload}` messages whenever `publish/3` is called
  for that user.

  The module is startable under a supervisor:

      children = [{Notifications, name: MyApp.Notifications}]

  Only OTP primitives are used — no external pub/sub dependency.
  """

  @default_name Notifications

  @typedoc "Name or pid of a running notifications server."
  @type server :: atom() | pid() | {atom(), node()} | {:via, module(), term()}

  @typedoc "Identifier of the user a notification belongs to."
  @type user_id :: term()

  @doc """
  Returns the child specification so `Notifications` can be started under a
  supervisor, e.g. `{Notifications, name: MyApp.Notifications}`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, @default_name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts the backing registry.

  Accepts a `:name` option used to register the process (defaults to
  `Notifications`). Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    Registry.start_link(keys: :duplicate, name: name, partitions: 1)
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  The caller will receive `{:notification, payload}` messages for every
  `publish/3` targeting the same `user_id`. Always returns `:ok`.
  """
  @spec subscribe(server(), user_id()) :: :ok
  def subscribe(server \\ @default_name, user_id) do
    {:ok, _owner} = Registry.register(server, user_id, nil)
    :ok
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.

  Returns `:ok`, including when there are no subscribers.
  """
  @spec publish(server(), user_id(), term()) :: :ok
  def publish(server \\ @default_name, user_id, payload) do
    Registry.dispatch(server, user_id, fn subscribers ->
      Enum.each(subscribers, fn {pid, _value} -> send(pid, {:notification, payload}) end)
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing a long-polling notifications endpoint.

  The plug subscribes the request process to `Notifications` for the user found
  at `conn.assigns.user_id` and then blocks in a `receive` until either a
  notification arrives or the configured timeout expires.

  Responses:

    * `200` with `content-type: application/json` and the JSON-encoded payload
      when a notification arrives in time;
    * `204` with an empty body when the timeout expires;
    * `401` with body `"unauthorized"` when `conn.assigns.user_id` is missing.

  Options:

    * `:notifications_server` — name or pid of the `Notifications` process
      (defaults to `Notifications`);
    * `:timeout_ms` — how long to hold the connection open (defaults to `30_000`).
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000

  @doc """
  Initializes the plug options, applying defaults for `:notifications_server`
  and `:timeout_ms`.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts
    |> Keyword.put_new(:notifications_server, Notifications)
    |> Keyword.put_new(:timeout_ms, @default_timeout_ms)
  end

  @doc """
  Handles a long-poll request, holding the connection open until a notification
  is published for the current user or the timeout elapses.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, opts) do
    case Map.get(conn.assigns, :user_id) do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(401, "unauthorized")

      user_id ->
        server = Keyword.get(opts, :notifications_server, Notifications)
        timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

        :ok = Notifications.subscribe(server, user_id)
        await_notification(conn, timeout_ms)
    end
  end

  @spec await_notification(Plug.Conn.t(), timeout()) :: Plug.Conn.t()
  defp await_notification(conn, timeout_ms) do
    receive do
      {:notification, payload} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(payload))
    after
      timeout_ms ->
        send_resp(conn, 204, "")
    end
  end
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the long-polling notifications endpoint.

  `GET /api/notifications/poll` is forwarded to `NotificationPoller`; every other
  request receives a `404`.

  The router accepts the same `:notifications_server` and `:timeout_ms` options as
  `NotificationPoller` and passes them straight through.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Initializes the router options, which are forwarded to `NotificationPoller`.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Dispatches the request, passing the router options through to the matched route.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts), do: super(conn, opts)

  get "/api/notifications/poll" do
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end