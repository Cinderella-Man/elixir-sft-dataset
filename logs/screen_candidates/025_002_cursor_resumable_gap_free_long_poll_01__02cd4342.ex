defmodule Notifications do
  @moduledoc """
  Sequenced pub/sub for per-user notifications, backed by a single `GenServer`.

  Each user has:

    * a monotonically increasing sequence counter (first published event gets `1`);
    * a bounded replay buffer of the most recent `{seq, payload}` tuples;
    * a set of subscriber processes, each monitored so that dead subscribers are
      dropped automatically.

  Subscribers receive `{:notification, seq, payload}` messages. Combining a live
  subscription with `events_since/3` lets a client resume from a cursor without
  missing events that were published while it was disconnected: subscribe first,
  then drain the buffer.

  Only OTP primitives are used — no `Registry`, no external pub/sub library.
  """

  use GenServer

  @default_buffer_size 100

  @typedoc "Identifier of the user a notification belongs to."
  @type user_id :: term()

  @typedoc "Per-user monotonic sequence number, starting at 1."
  @type seq :: pos_integer()

  @typedoc "An arbitrary, JSON-encodable notification payload."
  @type payload :: term()

  @typedoc "A buffered event: its sequence number and payload."
  @type event :: {seq(), payload()}

  defmodule State do
    @moduledoc false

    defstruct buffer_size: 100, users: %{}, monitors: %{}

    @type t :: %__MODULE__{
            buffer_size: pos_integer(),
            users: %{optional(term()) => %{seq: non_neg_integer(), buffer: [{pos_integer(), term()}]}},
            monitors: %{optional(reference()) => {pid(), term()}}
          }
  end

  @doc """
  Starts the notifications server.

  ## Options

    * `:name` — process registration name (default `Notifications`).
    * `:buffer_size` — maximum number of retained events per user (default `100`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  From then on, the caller receives `{:notification, seq, payload}` for every event
  published for that user. The server monitors the caller and removes the
  subscription when it exits. Subscribing twice is idempotent.
  """
  @spec subscribe(GenServer.server(), user_id()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    GenServer.call(server, {:subscribe, user_id, self()})
  end

  @doc """
  Publishes `payload` for `user_id`.

  Assigns the next sequence number for that user, appends the event to the replay
  buffer (evicting the oldest events beyond the configured buffer size), delivers
  `{:notification, seq, payload}` to every current subscriber, and returns
  `{:ok, seq}`.
  """
  @spec publish(GenServer.server(), user_id(), payload()) :: {:ok, seq()}
  def publish(server \\ __MODULE__, user_id, payload) do
    GenServer.call(server, {:publish, user_id, payload})
  end

  @doc """
  Returns the buffered events for `user_id` whose sequence number is strictly greater
  than `cursor`, oldest first.

  Returns `[]` when the user is unknown or has no newer buffered events.
  """
  @spec events_since(GenServer.server(), user_id(), non_neg_integer()) :: [event()]
  def events_since(server \\ __MODULE__, user_id, cursor) do
    GenServer.call(server, {:events_since, user_id, cursor})
  end

  @impl GenServer
  def init(opts) do
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    {:ok, %State{buffer_size: buffer_size}}
  end

  @impl GenServer
  def handle_call({:subscribe, user_id, pid}, _from, state) do
    user = user_state(state, user_id)

    if MapSet.member?(subscribers(state, user_id), pid) do
      {:reply, :ok, state}
    else
      ref = Process.monitor(pid)

      users =
        Map.put(state.users, user_id, %{user | subscribers: MapSet.put(user.subscribers, pid)})

      monitors = Map.put(state.monitors, ref, {pid, user_id})
      {:reply, :ok, %State{state | users: users, monitors: monitors}}
    end
  end

  def handle_call({:publish, user_id, payload}, _from, state) do
    user = user_state(state, user_id)
    seq = user.seq + 1
    buffer = trim(user.buffer ++ [{seq, payload}], state.buffer_size)

    Enum.each(user.subscribers, fn pid -> send(pid, {:notification, seq, payload}) end)

    users = Map.put(state.users, user_id, %{user | seq: seq, buffer: buffer})
    {:reply, {:ok, seq}, %State{state | users: users}}
  end

  def handle_call({:events_since, user_id, cursor}, _from, state) do
    events =
      state
      |> user_state(user_id)
      |> Map.fetch!(:buffer)
      |> Enum.filter(fn {seq, _payload} -> seq > cursor end)

    {:reply, events, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {{^pid, user_id}, monitors} ->
        user = user_state(state, user_id)
        subscribers = MapSet.delete(user.subscribers, pid)
        users = Map.put(state.users, user_id, %{user | subscribers: subscribers})
        {:noreply, %State{state | users: users, monitors: monitors}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Fetches (or lazily builds) the record for a user.
  defp user_state(state, user_id) do
    Map.get(state.users, user_id, %{seq: 0, buffer: [], subscribers: MapSet.new()})
  end

  defp subscribers(state, user_id), do: user_state(state, user_id).subscribers

  # Keeps at most `size` newest events, dropping from the front (oldest).
  defp trim(buffer, size) do
    case length(buffer) - size do
      drop when drop > 0 -> Enum.drop(buffer, drop)
      _none -> buffer
    end
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing a cursor-resumable, gap-free long poll for user notifications.

  The client issues `GET /api/notifications/poll?since=<cursor>`. The plug subscribes
  to the user's notification stream *before* inspecting the replay buffer — that
  ordering is what closes the classic long-poll gap, since any event published during
  the handoff is either already in the buffer or arrives as a live message.

  Responses:

    * `200` with `content-type: application/json`, an `x-notification-cursor` header
      holding the highest returned sequence number, and a body of the shape
      `{"cursor": <max_seq>, "events": [<payload>, ...]}`.
    * `204` with an empty body and an `x-notification-cursor` header echoing the
      request's `since` cursor, when the poll times out.
    * `401` with body `"unauthorized"` when `conn.assigns.user_id` is missing.

  ## Options

    * `:notifications_server` — the `Notifications` server (default `Notifications`).
    * `:timeout_ms` — how long to hold the connection open (default `30_000`).
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout_ms 30_000
  @cursor_header "x-notification-cursor"

  @doc """
  Initializes the plug options.

  Normalizes `:notifications_server` (default `Notifications`) and `:timeout_ms`
  (default `30_000`) into the options passed to `call/2`.
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
  Handles a long-poll request, holding the connection open until an event arrives or
  the configured timeout elapses.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case Map.get(conn.assigns, :user_id) do
      nil -> unauthorized(conn)
      user_id -> poll(conn, user_id, opts)
    end
  end

  defp poll(conn, user_id, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)

    conn = fetch_query_params(conn)
    since = parse_cursor(conn.query_params["since"])

    # Subscribe first, then read the buffer: an event published in between is captured
    # by one of the two paths, never lost by both.
    :ok = Notifications.subscribe(server, user_id)

    case Notifications.events_since(server, user_id, since) do
      [] -> await_notification(conn, since, timeout_ms)
      events -> respond_with_events(conn, events)
    end
  end

  defp await_notification(conn, since, timeout_ms) do
    receive do
      {:notification, seq, payload} -> respond_with_events(conn, [{seq, payload}])
    after
      timeout_ms -> no_content(conn, since)
    end
  end

  defp respond_with_events(conn, events) do
    max_seq = events |> Enum.map(fn {seq, _payload} -> seq end) |> Enum.max()
    payloads = Enum.map(events, fn {_seq, payload} -> payload end)
    body = Jason.encode!(%{"cursor" => max_seq, "events" => payloads})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header(@cursor_header, Integer.to_string(max_seq))
    |> send_resp(200, body)
  end

  defp no_content(conn, since) do
    conn
    |> put_resp_header(@cursor_header, Integer.to_string(since))
    |> send_resp(204, "")
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "unauthorized")
  end

  # Missing, negative, or non-integer cursors all mean "start from the beginning".
  defp parse_cursor(value) when is_binary(value) do
    case Integer.parse(value) do
      {cursor, ""} when cursor >= 0 -> cursor
      _other -> 0
    end
  end

  defp parse_cursor(_value), do: 0
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the long-poll notifications endpoint.

  `GET /api/notifications/poll` is handled by `NotificationPoller`; every other route
  returns `404`.

  ## Options

    * `:notifications_server` — forwarded to `NotificationPoller`.
    * `:timeout_ms` — forwarded to `NotificationPoller`.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Initializes the router options, keeping the poller-relevant keys.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    Keyword.take(opts, [:notifications_server, :timeout_ms])
  end

  @doc """
  Dispatches a request through the router's `match`/`dispatch` pipeline.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:notification_router_opts, opts)
    |> super(opts)
  end

  get "/api/notifications/poll" do
    opts = Map.get(conn.private, :notification_router_opts, [])
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end