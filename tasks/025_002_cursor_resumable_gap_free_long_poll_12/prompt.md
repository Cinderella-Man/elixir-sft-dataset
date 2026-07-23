# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `start_link`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me a set of Elixir modules that implement a **cursor-resumable, gap-free** long-polling notifications endpoint. Unlike a naive long poll (which silently drops any notification published in the window between two polls), this variant hands every response a monotonic **cursor** and keeps a short per-user replay buffer, so a client that echoes its last cursor back never misses an event — even one published while it was not connected.

## 1. `Notifications` module

This module manages sequenced pub/sub for user notifications. Back it with a `GenServer` (do **not** use `Registry`, since we must assign sequence numbers and retain recent history). It should provide:

- `Notifications.start_link(opts)` — starts the backing process. Accept a `:name` option for registration (default `Notifications`) and a `:buffer_size` option (max retained events per user, default `100`).

- `Notifications.subscribe(server \\ Notifications, user_id)` — subscribes the calling process to notifications for `user_id`. When an event is published, the subscribing process receives `{:notification, seq, payload}` where `seq` is the event's assigned sequence number. Returns `:ok`. The server must monitor subscribers and drop them on exit.

- `Notifications.publish(server \\ Notifications, user_id, payload)` — assigns the next per-user sequence number (starting at 1), appends `{seq, payload}` to that user's replay buffer (evicting oldest beyond `:buffer_size`), delivers `{:notification, seq, payload}` to all current subscribers, and returns `{:ok, seq}`.

- `Notifications.events_since(server \\ Notifications, user_id, cursor)` — returns the buffered `{seq, payload}` tuples for `user_id` whose `seq` is strictly greater than `cursor`, **oldest first**.

Use only OTP primitives (`GenServer`, `Process`). No Phoenix.PubSub, no external deps.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` for `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option and a `:timeout_ms` option (default `30_000`).

- Extract the user ID from `conn.assigns.user_id`. If missing, return 401 with body `"unauthorized"`.

- Read a `since` query parameter (an integer cursor; default `0`, and any missing/negative/garbage value is treated as `0`).

- **Subscribe first, then check the buffer** (this ordering is what closes the gap): after subscribing, call `events_since(server, user_id, since)`.
  - If the buffer already has newer events, respond immediately (do not block).
  - Otherwise, block on a `receive` with `after` waiting for a `{:notification, seq, payload}` message.

- A 200 response has `content-type: application/json`, a header `x-notification-cursor` set to the highest returned sequence number, and a JSON body of the shape `{"cursor": <max_seq>, "events": [<payload>, ...]}`. When answering from the buffer, include every newer event in order; when answering from a live message, include just that one event.

- On timeout, return 204 No Content with an empty body and an `x-notification-cursor` header echoing the request's `since` cursor (so the client resumes from where it was).

Use `Jason` for JSON encoding.

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`, passing through `:notifications_server` and `:timeout_ms`.
- Returns 404 for anything else.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a blocking `receive`), not a polling loop with `Process.sleep`.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.

## The module with `start_link` missing

```elixir
defmodule Notifications do
  @moduledoc """
  Sequenced in-memory pub/sub for user notifications, backed by a `GenServer`.

  Every published event for a user is assigned a strictly increasing per-user
  sequence number and appended to a bounded replay buffer. Subscribers receive
  `{:notification, seq, payload}` messages, and clients can ask for everything
  newer than a cursor via `events_since/3`, giving gap-free delivery across
  disconnected polls.
  """

  use GenServer

  @type server :: GenServer.server()
  @type user_id :: term()
  @type payload :: term()
  @type seq :: pos_integer()
  @type event :: {seq(), payload()}

  @default_buffer_size 100

  def start_link(opts \\ []) do
    # TODO
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.
  """
  @spec subscribe(server(), user_id()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    GenServer.call(server, {:subscribe, user_id, self()})
  end

  @doc """
  Publishes `payload` to `user_id`, returning `{:ok, seq}` with the assigned
  sequence number.
  """
  @spec publish(server(), user_id(), payload()) :: {:ok, seq()}
  def publish(server \\ __MODULE__, user_id, payload) do
    GenServer.call(server, {:publish, user_id, payload})
  end

  @doc """
  Returns buffered `{seq, payload}` tuples for `user_id` with `seq > cursor`,
  oldest first.
  """
  @spec events_since(server(), user_id(), non_neg_integer()) :: [event()]
  def events_since(server \\ __MODULE__, user_id, cursor) do
    GenServer.call(server, {:events_since, user_id, cursor})
  end

  # ------------------------------------------------------------------
  # Server callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      buffer_size: Keyword.get(opts, :buffer_size, @default_buffer_size),
      seq: %{},
      buf: %{},
      subs: %{},
      mons: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, user_id, pid}, _from, state) do
    ref = Process.monitor(pid)
    subs = Map.update(state.subs, user_id, [pid], fn pids -> [pid | pids] end)
    mons = Map.put(state.mons, ref, {user_id, pid})
    {:reply, :ok, %{state | subs: subs, mons: mons}}
  end

  def handle_call({:publish, user_id, payload}, _from, state) do
    seq = Map.get(state.seq, user_id, 0) + 1
    entry = {seq, payload}

    # Newest kept at the head; retain only the most recent buffer_size entries.
    buf =
      [entry | Map.get(state.buf, user_id, [])]
      |> Enum.take(state.buffer_size)

    state = %{
      state
      | seq: Map.put(state.seq, user_id, seq),
        buf: Map.put(state.buf, user_id, buf)
    }

    for pid <- Map.get(state.subs, user_id, []) do
      send(pid, {:notification, seq, payload})
    end

    {:reply, {:ok, seq}, state}
  end

  def handle_call({:events_since, user_id, cursor}, _from, state) do
    events =
      state.buf
      |> Map.get(user_id, [])
      |> Enum.reverse()
      |> Enum.filter(fn {seq, _payload} -> seq > cursor end)

    {:reply, events, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.mons, ref) do
      {nil, _mons} ->
        {:noreply, state}

      {{user_id, pid}, mons} ->
        subs = Map.update(state.subs, user_id, [], fn pids -> List.delete(pids, pid) end)
        {:noreply, %{state | subs: subs, mons: mons}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}
end

defmodule NotificationPoller do
  @moduledoc """
  Plug implementing cursor-resumable, gap-free long-polling for
  `GET /api/notifications/poll`.

  It subscribes first, then consults the replay buffer for anything newer than
  the request's `since` cursor. If the buffer already holds newer events they
  are returned immediately; otherwise it blocks on a `receive` until a live
  notification arrives or the timeout elapses. Because subscription happens
  before the buffer check, no event can slip through the gap.
  """

  import Plug.Conn

  @default_timeout_ms 30_000

  @doc """
  Initializes the plug, returning the given options unchanged.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Handles a poll request: authenticates, subscribes, and either replays buffered
  events, blocks for a live notification, or times out with a 204 response.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    conn = fetch_query_params(conn)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        cursor = parse_cursor(conn.query_params["since"])
        Notifications.subscribe(server, user_id)

        case Notifications.events_since(server, user_id, cursor) do
          [] -> wait_for_notification(conn, timeout, cursor)
          events -> respond_with_events(conn, events)
        end
    end
  end

  defp parse_cursor(nil), do: 0

  defp parse_cursor(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _rest} when n >= 0 -> n
      _ -> 0
    end
  end

  defp wait_for_notification(conn, timeout, cursor) do
    receive do
      {:notification, seq, payload} ->
        respond_with_events(conn, [{seq, payload}])
    after
      timeout ->
        conn
        |> put_resp_header("x-notification-cursor", Integer.to_string(cursor))
        |> send_resp(204, "")
    end
  end

  defp respond_with_events(conn, events) do
    {max_seq, _payload} = List.last(events)
    payloads = Enum.map(events, fn {_seq, payload} -> payload end)
    body = Jason.encode!(%{"cursor" => max_seq, "events" => payloads})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("x-notification-cursor", Integer.to_string(max_seq))
    |> send_resp(200, body)
  end
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` that forwards `GET /api/notifications/poll` to
  `NotificationPoller`, passing through the `:notifications_server` and
  `:timeout_ms` options, and returns 404 for everything else.
  """

  use Plug.Router, copy_opts_to_assign: :poller_opts

  plug(:match)
  plug(:dispatch)

  get "/api/notifications/poll" do
    opts = conn.assigns.poller_opts
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
```

Output only `start_link` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
