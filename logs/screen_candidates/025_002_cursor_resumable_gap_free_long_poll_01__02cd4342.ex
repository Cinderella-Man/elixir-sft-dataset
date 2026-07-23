defmodule Notifications do
  @moduledoc """
  Sequenced pub/sub for per-user notifications backed by a single `GenServer`.

  Every published event is assigned a strictly increasing, per-user sequence
  number (starting at `1`) and appended to a bounded replay buffer. Subscribers
  receive `{:notification, seq, payload}` messages, and clients can resume from a
  known cursor via `events_since/3` — closing the gap a naive long poll leaves
  open between two consecutive polls.

  Only OTP primitives are used (`GenServer`, `Process`); no `Registry`, no
  Phoenix.PubSub, and no external dependencies.
  """

  use GenServer

  @default_buffer_size 100

  @typedoc "Identifier for the user a notification belongs to."
  @type user_id :: term()

  @typedoc "A buffered event: its sequence number paired with its payload."
  @type event :: {pos_integer(), term()}

  @doc """
  Starts the notifications server.

  Options:

    * `:name` — process registration name (default `Notifications`).
    * `:buffer_size` — maximum retained events per user (default `100`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    GenServer.start_link(__MODULE__, buffer_size, name: name)
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  On each publish, the subscribed process receives `{:notification, seq,
  payload}`. The server monitors the subscriber and drops it automatically when
  it exits. Returns `:ok`.
  """
  @spec subscribe(GenServer.server(), user_id()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    GenServer.call(server, {:subscribe, user_id})
  end

  @doc """
  Publishes `payload` for `user_id`.

  Assigns the next per-user sequence number, appends the event to the replay
  buffer (evicting the oldest entries beyond `:buffer_size`), delivers
  `{:notification, seq, payload}` to all current subscribers, and returns
  `{:ok, seq}`.
  """
  @spec publish(GenServer.server(), user_id(), term()) :: {:ok, pos_integer()}
  def publish(server \\ __MODULE__, user_id, payload) do
    GenServer.call(server, {:publish, user_id, payload})
  end

  @doc """
  Returns buffered `{seq, payload}` events for `user_id` whose `seq` is strictly
  greater than `cursor`, oldest first.
  """
  @spec events_since(GenServer.server(), user_id(), non_neg_integer()) :: [event()]
  def events_since(server \\ __MODULE__, user_id, cursor) do
    GenServer.call(server, {:events_since, user_id, cursor})
  end

  @impl true
  @spec init(non_neg_integer()) :: {:ok, map()}
  def init(buffer_size) do
    state = %{
      buffer_size: buffer_size,
      seqs: %{},
      buffers: %{},
      subs: %{},
      monitors: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, user_id}, {pid, _tag}, state) do
    ref = Process.monitor(pid)
    subs = Map.update(state.subs, user_id, %{pid => ref}, &Map.put(&1, pid, ref))
    monitors = Map.put(state.monitors, ref, {user_id, pid})
    {:reply, :ok, %{state | subs: subs, monitors: monitors}}
  end

  def handle_call({:publish, user_id, payload}, _from, state) do
    seq = Map.get(state.seqs, user_id, 0) + 1
    buffer = Map.get(state.buffers, user_id, []) ++ [{seq, payload}]
    buffer = Enum.take(buffer, -state.buffer_size)
    subscribers = Map.get(state.subs, user_id, %{})
    Enum.each(subscribers, fn {pid, _ref} -> send(pid, {:notification, seq, payload}) end)

    state = %{
      state
      | seqs: Map.put(state.seqs, user_id, seq),
        buffers: Map.put(state.buffers, user_id, buffer)
    }

    {:reply, {:ok, seq}, state}
  end

  def handle_call({:events_since, user_id, cursor}, _from, state) do
    buffer = Map.get(state.buffers, user_id, [])
    events = Enum.filter(buffer, fn {seq, _payload} -> seq > cursor end)
    {:reply, events, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {{user_id, pid}, monitors} ->
        subs = Map.update(state.subs, user_id, %{}, &Map.delete(&1, pid))
        {:noreply, %{state | subs: subs, monitors: monitors}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing a cursor-resumable, gap-free long-poll endpoint for
  `GET /api/notifications/poll`.

  The plug subscribes the request process *before* inspecting the replay buffer.
  This ordering guarantees that any event published during the check is either
  already visible in the buffer or delivered as a live message — so a client that
  echoes its last cursor via `since` never misses an event.

  Options:

    * `:notifications_server` — the `Notifications` server (default
      `Notifications`).
    * `:timeout_ms` — how long to hold the connection open (default `30_000`).
  """

  import Plug.Conn

  @behaviour Plug

  @default_timeout_ms 30_000

  @impl true
  @doc "Plug init callback; returns the option keyword list unchanged."
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @doc """
  Handles a poll request: authenticates, subscribes, and either replies from the
  buffer, blocks for a live event, or times out with a 204.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    server = Keyword.get(opts, :notifications_server, Notifications)
    timeout = Keyword.get(opts, :timeout_ms) || @default_timeout_ms
    conn = fetch_query_params(conn)

    case Map.get(conn.assigns, :user_id) do
      nil -> send_resp(conn, 401, "unauthorized")
      user_id -> poll(conn, server, user_id, timeout)
    end
  end

  @spec poll(Plug.Conn.t(), GenServer.server(), term(), non_neg_integer()) ::
          Plug.Conn.t()
  defp poll(conn, server, user_id, timeout) do
    since = cursor_from(conn.query_params["since"])
    :ok = Notifications.subscribe(server, user_id)

    case Notifications.events_since(server, user_id, since) do
      [] -> wait_for_event(conn, since, timeout)
      events -> respond_events(conn, events)
    end
  end

  @spec wait_for_event(Plug.Conn.t(), non_neg_integer(), non_neg_integer()) ::
          Plug.Conn.t()
  defp wait_for_event(conn, since, timeout) do
    receive do
      {:notification, seq, payload} -> respond_live(conn, seq, payload)
    after
      timeout -> respond_timeout(conn, since)
    end
  end

  @spec respond_events(Plug.Conn.t(), [Notifications.event()]) :: Plug.Conn.t()
  defp respond_events(conn, events) do
    {cursor, _payload} = List.last(events)
    payloads = Enum.map(events, fn {_seq, payload} -> payload end)
    respond_json(conn, cursor, payloads)
  end

  @spec respond_live(Plug.Conn.t(), pos_integer(), term()) :: Plug.Conn.t()
  defp respond_live(conn, seq, payload) do
    respond_json(conn, seq, [payload])
  end

  @spec respond_json(Plug.Conn.t(), non_neg_integer(), [term()]) :: Plug.Conn.t()
  defp respond_json(conn, cursor, payloads) do
    body = Jason.encode!(%{"cursor" => cursor, "events" => payloads})

    conn
    |> put_resp_content_type("application/json", nil)
    |> put_resp_header("x-notification-cursor", Integer.to_string(cursor))
    |> send_resp(200, body)
  end

  @spec respond_timeout(Plug.Conn.t(), non_neg_integer()) :: Plug.Conn.t()
  defp respond_timeout(conn, since) do
    conn
    |> put_resp_header("x-notification-cursor", Integer.to_string(since))
    |> send_resp(204, "")
  end

  @spec cursor_from(term()) :: non_neg_integer()
  defp cursor_from(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _other -> 0
    end
  end

  defp cursor_from(_value), do: 0
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the notifications long-poll endpoint.

  `GET /api/notifications/poll` is forwarded to `NotificationPoller`, passing
  through the router's `:notifications_server` and `:timeout_ms` options. Any
  other request returns 404.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  get "/api/notifications/poll" do
    poller_opts =
      NotificationPoller.init(
        notifications_server: opts[:notifications_server],
        timeout_ms: opts[:timeout_ms]
      )

    NotificationPoller.call(conn, poller_opts)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end