defmodule CacheLayer do
  @moduledoc """
  An ETS-backed read-through cache with a single-flight (request-coalescing),
  non-blocking concurrency model.

  ## Design

  A `CacheLayer` process owns one `:set`/`:public` ETS table per logical `table`
  atom (created lazily on first use). It coordinates *who* loads a missing key,
  but it never runs the expensive `fallback_fn` itself:

    * **Cache hits bypass the GenServer entirely.** The ETS tid for a table is
      published in `:persistent_term`, so `fetch/4` reads straight from ETS with
      no message passing at all.

    * **Cache misses are coalesced per key.** The first caller to miss on
      `{table, key}` becomes the *leader* and runs `fallback_fn` **in its own
      process**. Concurrent callers for the same key become *followers*: their
      `GenServer.call/3` reply is deferred until the leader publishes a value,
      at which point every follower is replied to with that value. `fallback_fn`
      therefore runs **at most once** per cache miss, regardless of how many
      processes race.

    * **Distinct keys never block each other.** Because the slow work happens in
      the caller (outside the server's critical section), the server only ever
      does cheap bookkeeping — a slow load of key `A` cannot delay a load of key
      `B`.

    * **Leaders are supervised.** The server monitors the leader. If the leader
      crashes (or reports a failure) before publishing a value, one waiting
      follower is promoted to leader and gets to retry; followers never hang.

  ## Cleanup

  The server traps exits and owns every ETS table it creates, so the tables die
  with it. Its `terminate/2` callback erases every `:persistent_term` entry it
  registered, so a cleanly stopped cache leaves nothing behind.

  ## Example

      {:ok, _pid} = CacheLayer.start_link(name: MyCache)

      {:ok, user} = CacheLayer.fetch(MyCache, :users, 42, fn -> Repo.get(User, 42) end)
      :ok = CacheLayer.invalidate(MyCache, :users, 42)
      :ok = CacheLayer.invalidate_all(MyCache, :users)
  """

  use GenServer

  @typedoc "Logical cache table name; each maps to one ETS table."
  @type table :: atom()

  @typedoc "Any term usable as an ETS key."
  @type key :: term()

  @typedoc "Any cached term."
  @type value :: term()

  @typedoc "Zero-arity loader run outside the GenServer on a cache miss."
  @type fallback :: (-> value())

  ## ---------------------------------------------------------------------------
  ## Public API
  ## ---------------------------------------------------------------------------

  @doc """
  Starts the cache process.

  ## Options

    * `:name` - optional name used to register the process (any valid
      `t:GenServer.name/0`).

  The started process owns the lifecycle of every ETS table it creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Reads `key` from `table`, computing it with `fallback_fn` on a cache miss.

  Always returns `{:ok, value}`.

  On a hit the value is read directly from ETS with no GenServer round-trip. On
  a miss the caller joins the single-flight protocol for `{table, key}`: it
  either becomes the leader and evaluates `fallback_fn` in its own process, or
  it blocks until the current leader publishes the value.

  `fallback_fn` is a zero-arity function and is invoked at most once per cache
  miss, no matter how many processes miss concurrently. If `fallback_fn` raises,
  throws or exits, the failure is propagated to the caller and one of the
  waiting followers (if any) is promoted to retry the load.
  """
  @spec fetch(GenServer.server(), table(), key(), fallback()) :: {:ok, value()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    case ets_lookup(server, table, key) do
      {:ok, value} -> {:ok, value}
      :miss -> fetch_miss(server, table, key, fallback_fn)
    end
  end

  @doc """
  Removes the cached entry for `{table, key}`.

  Returns `:ok`, also when nothing was cached for that key.
  """
  @spec invalidate(GenServer.server(), table(), key()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key, server}, :infinity)
  end

  @doc """
  Removes every cached entry belonging to `table`.

  The ETS table itself is kept (and stays owned by the cache process); only its
  contents are cleared. Returns `:ok`.
  """
  @spec invalidate_all(GenServer.server(), table()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table, server}, :infinity)
  end

  ## ---------------------------------------------------------------------------
  ## Client-side miss handling (runs in the *caller* process)
  ## ---------------------------------------------------------------------------

  defp fetch_miss(server, table, key, fallback_fn) do
    # `server` is passed along so the server can publish the ETS tid under the
    # exact alias this caller uses to address it.
    case GenServer.call(server, {:join, table, key, server}, :infinity) do
      {:value, value} -> {:ok, value}
      {:lead, tid} -> lead(server, table, key, tid, fallback_fn)
    end
  end

  # Runs OUTSIDE the GenServer: the slow work happens here, in the caller.
  defp lead(server, table, key, tid, fallback_fn) do
    value = fallback_fn.()
    :ets.insert(tid, {key, value})
    :ok = GenServer.call(server, {:done, table, key, value}, :infinity)
    {:ok, value}
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__
      GenServer.cast(server, {:failed, table, key, self()})
      :erlang.raise(kind, reason, stacktrace)
  end

  defp ets_lookup(server, table, key) do
    case :persistent_term.get(pt_key(server, table), nil) do
      nil -> :miss
      tid -> safe_lookup(tid, key)
    end
  end

  # The tid may be stale (e.g. the cache was restarted); treat that as a miss.
  defp safe_lookup(tid, key) do
    case :ets.lookup(tid, key) do
      [{_key, value}] -> {:ok, value}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp pt_key(server, table), do: {__MODULE__, server, table}

  ## ---------------------------------------------------------------------------
  ## GenServer callbacks
  ## ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       # table atom => ETS tid
       tables: %{},
       # {table, key} => %{leader_pid: pid, leader_ref: reference, waiters: [from]}
       inflight: %{},
       # monitor reference => {table, key}
       monitors: %{},
       # every :persistent_term key we published
       pt_keys: MapSet.new()
     }}
  end

  @impl GenServer
  def handle_call({:join, table, key, server_ref}, from, state) do
    {tid, state} = ensure_table(table, server_ref, state)

    case :ets.lookup(tid, key) do
      [{_key, value}] -> {:reply, {:value, value}, state}
      [] -> join_inflight(table, key, tid, from, state)
    end
  end

  def handle_call({:done, table, key, value}, {pid, _tag}, state) do
    id = {table, key}

    case Map.fetch(state.inflight, id) do
      {:ok, %{leader_pid: ^pid, waiters: waiters} = entry} ->
        Enum.each(waiters, &GenServer.reply(&1, {:value, value}))
        {:reply, :ok, forget(state, id, entry)}

      _other ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:invalidate, table, key, server_ref}, _from, state) do
    {tid, state} = ensure_table(table, server_ref, state)
    :ets.delete(tid, key)
    {:reply, :ok, state}
  end

  def handle_call({:invalidate_all, table, server_ref}, _from, state) do
    {tid, state} = ensure_table(table, server_ref, state)
    :ets.delete_all_objects(tid)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:failed, table, key, pid}, state) do
    id = {table, key}

    case Map.fetch(state.inflight, id) do
      {:ok, %{leader_pid: ^pid} = entry} -> {:noreply, promote(state, id, entry)}
      _other -> {:noreply, state}
    end
  end

  def handle_cast(_message, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.fetch(state.monitors, ref) do
      {:ok, id} ->
        case Map.fetch(state.inflight, id) do
          {:ok, entry} -> {:noreply, promote(state, id, entry)}
          :error -> {:noreply, %{state | monitors: Map.delete(state.monitors, ref)}}
        end

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.pt_keys, &:persistent_term.erase/1)
    :ok
  end

  ## ---------------------------------------------------------------------------
  ## Server-side helpers (cheap bookkeeping only — never the fallback)
  ## ---------------------------------------------------------------------------

  defp join_inflight(table, key, tid, {pid, _tag} = from, state) do
    id = {table, key}

    case Map.fetch(state.inflight, id) do
      :error ->
        ref = Process.monitor(pid)
        entry = %{leader_pid: pid, leader_ref: ref, waiters: []}

        state = %{
          state
          | inflight: Map.put(state.inflight, id, entry),
            monitors: Map.put(state.monitors, ref, id)
        }

        {:reply, {:lead, tid}, state}

      {:ok, entry} ->
        # Follower: the reply is deferred until the leader publishes a value.
        entry = %{entry | waiters: entry.waiters ++ [from]}
        {:noreply, %{state | inflight: Map.put(state.inflight, id, entry)}}
    end
  end

  # The leader is gone without a value: hand leadership to a waiting follower so
  # nobody blocks forever, or drop the in-flight entry if nobody is waiting.
  defp promote(state, {table, _key} = id, entry) do
    state = drop_leader(state, entry)

    case entry.waiters do
      [] ->
        %{state | inflight: Map.delete(state.inflight, id)}

      [{pid, _tag} = next | rest] ->
        tid = Map.fetch!(state.tables, table)
        ref = Process.monitor(pid)
        GenServer.reply(next, {:lead, tid})
        new_entry = %{leader_pid: pid, leader_ref: ref, waiters: rest}

        %{
          state
          | inflight: Map.put(state.inflight, id, new_entry),
            monitors: Map.put(state.monitors, ref, id)
        }
    end
  end

  defp forget(state, id, entry) do
    state = drop_leader(state, entry)
    %{state | inflight: Map.delete(state.inflight, id)}
  end

  defp drop_leader(state, %{leader_ref: ref}) do
    Process.demonitor(ref, [:flush])
    %{state | monitors: Map.delete(state.monitors, ref)}
  end

  defp ensure_table(table, server_ref, state) do
    {tid, state} =
      case Map.fetch(state.tables, table) do
        {:ok, tid} ->
          {tid, state}

        :error ->
          opts = [:set, :public, {:read_concurrency, true}, {:write_concurrency, true}]
          tid = :ets.new(table, opts)
          {tid, %{state | tables: Map.put(state.tables, table, tid)}}
      end

    state =
      state
      |> publish(server_ref, table, tid)
      |> publish(self(), table, tid)

    {tid, state}
  end

  defp publish(state, server_ref, table, tid) do
    pt_key = pt_key(server_ref, table)

    if MapSet.member?(state.pt_keys, pt_key) do
      state
    else
      :persistent_term.put(pt_key, tid)
      %{state | pt_keys: MapSet.put(state.pt_keys, pt_key)}
    end
  end
end