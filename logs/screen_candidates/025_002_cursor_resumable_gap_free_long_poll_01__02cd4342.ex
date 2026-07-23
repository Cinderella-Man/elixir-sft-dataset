defmodule Notifications do
  @moduledoc """
  Sequenced pub/sub for per-user notifications, backed by a single `GenServer`.

  Every published event is assigned a strictly monotonic, per-user sequence
  number (starting at `1`) and appended to a bounded, per-user replay buffer.
  Subscribers receive `{:notification, seq, payload}` messages, while late or
  reconnecting clients can catch up on missed events via `events_since/3`.

  This combination — a shared sequence counter plus retained history — is why a
  plain `Registry` is unsuitable here, so an explicit `GenServer` is used. Only
  OTP primitives (`GenServer` and `Process`) are involved; there is no external
  pub/sub dependency.
  """

  use GenServer

  @default_name __MODULE__
  @default_buffer_size 100

  @typedoc "Opaque identifier of a user (any term)."
  @type user_id :: term()

  @typedoc "A per-user, strictly increasing sequence number."
  @type seq :: pos_integer()

  @typedoc "An arbitrary, JSON-encodable notification payload."
  @type payload :: term()

  @typedoc "A buffered event: its sequence number paired with its payload."
  @type event :: {seq(), payload()}

  @typedoc "Internal server state."
  @type state :: %{
          buffer_size: non_neg_integer(),
          users: %{optional(user_id()) => map()},
          monitors: %{optional(pid()) => reference()}
        }

  ## Client API

  @doc """
  Starts the notifications server.

  Options:

    * `:name` — process registration name (default `#{inspect(@default_name)}`).
    * `:buffer_size` — max retained events per user (default `#{@default_buffer_size}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.

  The subscribing process will receive `{:notification, seq, payload}` messages
  as events are published. The server monitors the subscriber and drops it
  automatically when it exits. Always returns `:ok`.
  """
  @spec subscribe(GenServer.server(), user_id()) :: :ok
  def subscribe(server \\ @default_name, user_id) do
    GenServer.call(server, {:subscribe, user_id})
  end

  @doc """
  Publishes `payload` for `user_id`.

  Assigns the next per-user sequence number, appends the event to the replay
  buffer (evicting the oldest entries beyond `:buffer_size`), delivers
  `{:notification, seq, payload}` to all current subscribers, and returns
  `{:ok, seq}`.
  """
  @spec publish(GenServer.server(), user_id(), payload()) :: {:ok, seq()}
  def publish(server \\ @default_name, user_id, payload) do
    GenServer.call(server, {:publish, user_id, payload})
  end

  @doc """
  Returns the buffered `{seq, payload}` tuples for `user_id` whose sequence
  number is strictly greater than `cursor`, oldest first.
  """
  @spec events_since(GenServer.server(), user_id(), non_neg_integer()) :: [event()]
  def events_since(server \\ @default_name, user_id, cursor) do
    GenServer.call(server, {:events_since, user_id, cursor})
  end

  ## Server callbacks

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    {:ok, %{buffer_size: buffer_size, users: %{}, monitors: %{}}}
  end

  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), state()) :: {:reply, term(), state()}
  def handle_call({:subscribe, user_id}, {pid, _tag}, state) do
    state = monitor_pid(state, pid)
    user = get_user(state, user_id)
    user = %{user | subs: MapSet.put(user.subs, pid)}
    {:reply, :ok, put_user(state, user_id, user)}
  end

  def handle_call({:publish, user_id, payload}, _from, state) do
    user = get_user(state, user_id)
    seq = user.next_seq
    buffer = Enum.take(user.buffer ++ [{seq, payload}], -state.buffer_size)
    user = %{user | next_seq: seq + 1, buffer: buffer}

    Enum.each(user.subs, fn pid ->
      send(pid, {:notification, seq, payload})
    end)

    {:reply, {:ok, seq}, put_user(state, user_id, user)}
  end

  def handle_call({:events_since, user_id, cursor}, _from, state) do
    user = get_user(state, user_id)
    events = Enum.filter(user.buffer, fn {seq, _payload} -> seq > cursor end)
    {:reply, events, state}
  end

  @doc false
  @impl true
  @spec handle_info(term(), state()) :: {:noreply, state()}
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    users =
      Map.new(state.users, fn {uid, user} ->
        {uid, %{user | subs: MapSet.delete(user.subs, pid)}}
      end)

    {:noreply, %{state | users: users, monitors: Map.delete(state.monitors, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal helpers

  defp monitor_pid(state, pid) do
    if Map.has_key?(state.monitors, pid) do
      state
    else
      ref = Process.monitor(pid)
      %{state | monitors: Map.put(state.monitors, pid, ref)}
    end
  end

  defp get_user(state, user_id) do
    Map.get(state.users, user_id, %{next_seq: 1, buffer: [], subs: MapSet.new()})
  end

  defp put_user(state, user_id, user) do
    %{state | users: Map.put(state.users, user_id, user)}
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A `Plug` implementing a cursor-resumable, gap-free long-poll endpoint for
  `GET /api/notifications/poll`.

  The gap between two naive long polls is closed by subscribing *before*
  inspecting the replay buffer: any event published in the meantime is either
  already present in the buffer (answered immediately) or delivered as a live
  `{:notification, seq, payload}` message to the blocking `receive`.

  Every 200 response carries an `x-notification-cursor` header set to the
  highest returned sequence number, so a client can echo it back via the `since`
  query parameter and never miss an event. On timeout a `204 No Content` echoes
  the request cursor unchanged.
  """

  @behaviour Plug

  import Plug.Conn

  @default_timeout 30_000

  @doc """
  Plug initialization. Options are passed through verbatim; `:notifications_server`
  is required and `:timeout_ms` defaults to `#{@default_timeout}`.
  """
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Handles a single long-poll request, blocking until an event is available or
  the configured timeout elapses.
  """
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case conn.assigns[:user_id] do
      nil ->
        conn |> send_resp(401, "unauthorized") |> halt()

      user_id ->
        handle_poll(conn, opts, user_id)
    end
  end

  ## Internal helpers

  defp handle_poll(conn, opts, user_id) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout)
    conn = fetch_query_params(conn)
    since = parse_cursor(conn.query_params["since"])

    :ok = Notifications.subscribe(server, user_id)

    case Notifications.events_since(server, user_id, since) do
      [] -> await_notification(conn, since, timeout)
      events -> respond_events(conn, events)
    end
  end

  defp await_notification(conn, since, timeout) do
    receive do
      {:notification, seq, payload} ->
        json_response(conn, seq, [payload])
    after
      timeout ->
        conn
        |> put_resp_header("x-notification-cursor", Integer.to_string(since))
        |> send_resp(204, "")
    end
  end

  defp respond_events(conn, events) do
    {max_seq, _payload} = List.last(events)
    payloads = Enum.map(events, fn {_seq, payload} -> payload end)
    json_response(conn, max_seq, payloads)
  end

  defp json_response(conn, cursor, payloads) do
    body = Jason.encode!(%{cursor: cursor, events: payloads})

    conn
    |> put_resp_header("content-type", "application/json")
    |> put_resp_header("x-notification-cursor", Integer.to_string(cursor))
    |> send_resp(200, body)
  end

  defp parse_cursor(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end

  defp parse_cursor(_value), do: 0
end

defmodule NotificationRouter do
  @moduledoc """
  A thin `Plug.Router` exposing the long-poll notifications endpoint.

  It forwards `GET /api/notifications/poll` to `NotificationPoller`, threading
  the router's runtime options (`:notifications_server` and `:timeout_ms`)
  through via `builder_opts/0`, and answers `404` for every other request.
  """

  use Plug.Router

  plug :match
  plug :dispatch, builder_opts()

  get "/api/notifications/poll" do
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end