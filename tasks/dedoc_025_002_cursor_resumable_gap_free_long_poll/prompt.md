# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Notifications do
  use GenServer

  @default_buffer_size 100

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def subscribe(server \\ __MODULE__, user_id) do
    GenServer.call(server, {:subscribe, user_id, self()})
  end

  def publish(server \\ __MODULE__, user_id, payload) do
    GenServer.call(server, {:publish, user_id, payload})
  end

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
  import Plug.Conn

  @default_timeout_ms 30_000

  def init(opts), do: opts

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
