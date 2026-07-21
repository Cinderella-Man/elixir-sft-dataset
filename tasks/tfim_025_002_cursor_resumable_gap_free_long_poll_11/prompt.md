# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @doc """
  Starts the backing `GenServer`.

  Options:
    * `:name` — registration name and server reference (default `Notifications`)
    * `:buffer_size` — max retained events per user (default `100`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
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

## Test harness — implement the `# TODO` test

```elixir
defmodule CursorLongPollTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  # -------------------------------------------------------
  # Setup — a fresh sequenced Notifications server per test
  # -------------------------------------------------------

  setup do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server})

    opts = [
      notifications_server: server,
      timeout_ms: 500
    ]

    %{server: server, opts: opts}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp poll(opts, user_id, since) do
    :get
    |> conn("/api/notifications/poll?since=#{since}")
    |> assign(:user_id, user_id)
    |> NotificationRouter.call(NotificationRouter.init(opts))
  end

  defp decode(conn), do: Jason.decode!(conn.resp_body)

  defp cursor_header(conn), do: get_resp_header(conn, "x-notification-cursor")

  # -------------------------------------------------------
  # Gap-free semantics — the whole point of this variant
  # -------------------------------------------------------

  test "an event published BEFORE the poll is not missed (replayed from buffer)",
       %{server: server, opts: opts} do
    # Nobody is connected yet.
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"body" => "early"})

    # Now the client polls from the beginning — a naive long poll would block
    # and eventually 204, losing the event. This one replays it immediately.
    conn = poll(opts, "user:1", 0)

    assert conn.status == 200
    assert hd(get_resp_header(conn, "content-type")) =~ "application/json"
    assert decode(conn) == %{"cursor" => 1, "events" => [%{"body" => "early"}]}
    assert cursor_header(conn) == ["1"]
  end

  test "multiple buffered events replay in order with the highest cursor",
       %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"n" => 1})
    assert {:ok, 2} = Notifications.publish(server, "user:1", %{"n" => 2})
    assert {:ok, 3} = Notifications.publish(server, "user:1", %{"n" => 3})

    conn = poll(opts, "user:1", 0)

    assert conn.status == 200

    assert decode(conn) == %{
             "cursor" => 3,
             "events" => [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}]
           }

    assert cursor_header(conn) == ["3"]
  end

  test "resuming from a cursor returns only newer events, no duplicates",
       %{server: server, opts: opts} do
    Notifications.publish(server, "user:1", %{"n" => 1})

    conn1 = poll(opts, "user:1", 0)
    assert conn1.status == 200
    assert decode(conn1)["cursor"] == 1
    assert decode(conn1)["events"] == [%{"n" => 1}]

    # More arrive; the client resumes from cursor 1.
    Notifications.publish(server, "user:1", %{"n" => 2})
    Notifications.publish(server, "user:1", %{"n" => 3})

    conn2 = poll(opts, "user:1", 1)
    assert conn2.status == 200
    assert decode(conn2) == %{"cursor" => 3, "events" => [%{"n" => 2}, %{"n" => 3}]}
  end

  # -------------------------------------------------------
  # Live blocking delivery
  # -------------------------------------------------------

  test "blocks and returns a notification that arrives during the poll",
       %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:1", %{"live" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    assert decode(conn) == %{"cursor" => 1, "events" => [%{"live" => true}]}
    assert cursor_header(conn) == ["1"]
  end

  test "204 on timeout echoes the request cursor so the client can resume",
       %{server: server, opts: opts} do
    # Advance the cursor to 2, then poll from 2 with nothing new.
    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})

    conn = poll(opts, "user:1", 2)

    assert conn.status == 204
    assert conn.resp_body == ""
    assert cursor_header(conn) == ["2"]
  end

  # -------------------------------------------------------
  # Cursor parsing robustness
  # -------------------------------------------------------

  test "missing / garbage / negative since is treated as 0", %{server: server, opts: opts} do
    Notifications.publish(server, "user:1", %{"n" => 1})

    for since <- ["", "abc", "-5", "not_a_number"] do
      conn =
        :get
        |> conn("/api/notifications/poll?since=#{since}")
        |> assign(:user_id, "user:1")
        |> NotificationRouter.call(NotificationRouter.init(opts))

      assert conn.status == 200
      assert decode(conn)["events"] == [%{"n" => 1}]
    end
  end

  # -------------------------------------------------------
  # Auth
  # -------------------------------------------------------

  test "401 when user_id is absent", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?since=0")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
    assert conn.resp_body == "unauthorized"
  end

  # -------------------------------------------------------
  # User isolation
  # -------------------------------------------------------

  test "events for user A do not leak to user B", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:a", %{"for" => "a"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
    assert cursor_header(conn_b) == ["0"]
  end

  test "per-user sequences are independent", %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:a", %{"x" => "a1"})
    assert {:ok, 1} = Notifications.publish(server, "user:b", %{"x" => "b1"})
    assert {:ok, 2} = Notifications.publish(server, "user:a", %{"x" => "a2"})

    conn_a = poll(opts, "user:a", 0)
    conn_b = poll(opts, "user:b", 0)

    assert decode(conn_a) == %{"cursor" => 2, "events" => [%{"x" => "a1"}, %{"x" => "a2"}]}
    assert decode(conn_b) == %{"cursor" => 1, "events" => [%{"x" => "b1"}]}
  end

  # -------------------------------------------------------
  # Fan-out to multiple live pollers
  # -------------------------------------------------------

  test "multiple live pollers for the same user all receive the event",
    # TODO
  end

  # -------------------------------------------------------
  # Buffer eviction
  # -------------------------------------------------------

  test "buffer retains only the most recent :buffer_size events" do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server, buffer_size: 3})

    for n <- 1..5, do: Notifications.publish(server, "user:1", %{"n" => n})

    # Only seqs 3,4,5 survive; asking since 0 still returns them oldest-first.
    events = Notifications.events_since(server, "user:1", 0)
    assert events == [{3, %{"n" => 3}}, {4, %{"n" => 4}}, {5, %{"n" => 5}}]
  end

  # -------------------------------------------------------
  # Router
  # -------------------------------------------------------

  test "router returns 404 for unknown paths", %{opts: opts} do
    conn =
      :get
      |> conn("/api/unknown")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 404
  end

  # -------------------------------------------------------
  # Notifications unit tests
  # -------------------------------------------------------

  test "publish assigns monotonic sequences and delivers with seq", %{server: server} do
    Notifications.subscribe(server, "user:direct")

    assert {:ok, 1} = Notifications.publish(server, "user:direct", %{"a" => 1})
    assert {:ok, 2} = Notifications.publish(server, "user:direct", %{"a" => 2})

    assert_receive {:notification, 1, %{"a" => 1}}, 500
    assert_receive {:notification, 2, %{"a" => 2}}, 500
  end

  test "events_since filters strictly greater than cursor", %{server: server} do
    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})
    Notifications.publish(server, "user:1", %{"n" => 3})

    assert Notifications.events_since(server, "user:1", 0) ==
             [{1, %{"n" => 1}}, {2, %{"n" => 2}}, {3, %{"n" => 3}}]

    assert Notifications.events_since(server, "user:1", 2) == [{3, %{"n" => 3}}]
    assert Notifications.events_since(server, "user:1", 3) == []
  end

  test "publish to a user with no subscribers does not crash", %{server: server} do
    assert {:ok, 1} = Notifications.publish(server, "nobody", %{"ignored" => true})
  end

  test "dead subscribers are dropped and do not accumulate", %{server: server} do
    {:ok, agent} = Agent.start(fn -> :ok end)
    Agent.get(agent, fn _ -> Notifications.subscribe(server, "user:1") end)
    ref = Process.monitor(agent)
    Agent.stop(agent)
    assert_receive {:DOWN, ^ref, :process, ^agent, _}, 500

    # Publishing after the subscriber died must still succeed.
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"n" => 1})
  end

  # -------------------------------------------------------
  # Subscribe-before-buffer-check ordering
  # -------------------------------------------------------

  # Busy work used to vary where a concurrent publish lands relative to the
  # start of a poll. It is jitter only — no assertion depends on its duration.
  defp burn(0), do: :ok
  defp burn(n), do: burn(n - 1)

  test "a poll answered from the buffer has still subscribed the caller",
       %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:order", %{"n" => 1})

    conn = poll(opts, "user:order", 0)
    assert conn.status == 200
    assert decode(conn) == %{"cursor" => 1, "events" => [%{"n" => 1}]}

    # Subscription precedes the buffer check, so the polling process is a live
    # subscriber even though its response came straight from the buffer.
    assert {:ok, 2} = Notifications.publish(server, "user:order", %{"n" => 2})
    assert_receive {:notification, 2, %{"n" => 2}}, 500
  end

  test "an event published concurrently with the start of a poll is never lost" do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server, buffer_size: 5_000})
    opts = [notifications_server: server, timeout_ms: 1_000]
    user = "user:race"

    # A deep buffer of already-consumed history: every buffer check has real
    # work to do, so a publish has a genuine chance of landing between the
    # poller's subscribe and its buffer check.
    for n <- 1..2_000, do: Notifications.publish(server, user, %{"warm" => n})

    Enum.each(1..40, fn i ->
      since = 1_999 + i
      task = Task.async(fn -> poll(opts, user, since) end)
      burn(i * 500)

      assert {:ok, seq} = Notifications.publish(server, user, %{"race" => i})
      assert seq == since + 1

      # Whether the event lands before, during, or after the poll's setup, the
      # client must see it rather than a 204 that silently drops it.
      conn = Task.await(task, 5_000)
      assert conn.status == 200
      assert decode(conn) == %{"cursor" => seq, "events" => [%{"race" => i}]}
      assert cursor_header(conn) == [Integer.to_string(seq)]
    end)
  end
end
```
