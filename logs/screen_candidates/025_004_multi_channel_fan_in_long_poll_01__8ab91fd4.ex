defmodule Notifications do
  @moduledoc """
  Per-`{user_id, channel}` publish/subscribe built on a `Registry` in `:duplicate` mode.

  Each subscriber registers itself under the key `{user_id, channel}`. Publishing to that
  pair sends `{:notification, channel, payload}` to every registered process, so a single
  process can subscribe to many channels and receive messages from all of them in one
  mailbox — which is what makes a fan-in long poll possible with one blocking `receive`.

  Only OTP primitives are used; there is no external pub/sub dependency.
  """

  @typedoc "Identifier of the user owning a notification stream."
  @type user_id :: term()

  @typedoc "Name of a channel within a user's notification space."
  @type channel :: String.t()

  @doc """
  Starts the `Registry` backing the pub/sub.

  Options:

    * `:name` — the registry name used by `subscribe/3` and `publish/4` (default `Notifications`).

  Any other options are passed through to `Registry.start_link/1`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    opts
    |> Keyword.merge(keys: :duplicate, name: name)
    |> Registry.start_link()
  end

  @doc """
  Returns a child specification so the server can be placed in a supervision tree.
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
  Subscribes the calling process to `{user_id, channel}`.

  From then on, every `publish/4` to that pair delivers `{:notification, channel, payload}`
  to the caller's mailbox. Subscribing more than once simply delivers more than once.
  """
  @spec subscribe(atom() | pid(), user_id(), channel()) :: :ok
  def subscribe(server \\ __MODULE__, user_id, channel) do
    {:ok, _owner} = Registry.register(server, {user_id, channel}, nil)
    :ok
  end

  @doc """
  Publishes `payload` to every process subscribed to `{user_id, channel}`.

  Delivery is fire-and-forget: this always returns `:ok`, even when nobody is listening.
  """
  @spec publish(atom() | pid(), user_id(), channel(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, channel, payload) do
    Registry.dispatch(server, {user_id, channel}, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, channel, payload})
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  Plug implementing `GET /api/notifications/poll` as a multi-channel fan-in long poll.

  A client names several channels via the `channels` query parameter (comma separated, e.g.
  `?channels=orders,alerts,dm`). The plug subscribes to `{user_id, channel}` for each one and
  then blocks in a single `receive` until the first notification arrives on *any* of them, or
  until the configured timeout expires.

  Responses:

    * `200` with `{"channel": ..., "payload": ...}` — the first notification, tagged with its
      originating channel;
    * `204` with an empty body — the timeout expired with nothing to report;
    * `400` `"no channels"` — the `channels` parameter was absent or empty;
    * `401` `"unauthorized"` — `conn.assigns.user_id` was missing.

  Options:

    * `:notifications_server` — the `Notifications` registry name (default `Notifications`);
    * `:timeout_ms` — how long to hold the connection open (default `30_000`).
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000

  @doc """
  Normalises the plug options at compile/init time.
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
  Handles a poll request: authenticates, subscribes to every requested channel and waits for
  the first notification on any of them.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    with {:ok, user_id} <- fetch_user_id(conn),
         conn = fetch_query_params(conn),
         {:ok, channels} <- fetch_channels(conn) do
      await_notification(conn, user_id, channels, opts)
    else
      {:error, :unauthorized} ->
        send_resp(conn, 401, "unauthorized")

      {:error, :no_channels} ->
        send_resp(conn, 400, "no channels")
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

  @spec await_notification(Plug.Conn.t(), term(), [String.t()], keyword()) :: Plug.Conn.t()
  defp await_notification(conn, user_id, channels, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)

    Enum.each(channels, &Notifications.subscribe(server, user_id, &1))

    receive do
      {:notification, channel, payload} ->
        body = Jason.encode!(%{"channel" => channel, "payload" => payload})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, body)
    after
      timeout_ms ->
        send_resp(conn, 204, "")
    end
  end
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` exposing the multi-channel long-poll endpoint.

  Forwards `GET /api/notifications/poll` to `NotificationPoller` and answers everything else
  with `404`. The `:notifications_server` and `:timeout_ms` options are accepted here and
  handed straight through to the poller.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Stores the router options so `dispatch/2` can forward them to `NotificationPoller`.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Runs the `match`/`dispatch` pipeline for the given connection.
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
    send_resp(conn, 404, "not found")
  end
end