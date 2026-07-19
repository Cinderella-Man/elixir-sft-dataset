# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed cache using a **single-flight (request-coalescing), non-blocking** concurrency model.

The naive design serialises *every* cache miss through the GenServer and runs the slow `fallback_fn` inside the GenServer's critical section — so one slow database call blocks misses for **all** keys. I want a better concurrency model:

- The expensive `fallback_fn` must run **outside** the GenServer process, so a slow load for one key never blocks loads for other keys — distinct keys are computed concurrently.
- For a single key, if several callers miss at the same time, exactly **one** of them (the "leader") runs `fallback_fn`; the others ("followers") block until the leader finishes and then receive the leader's result. `fallback_fn` is called **at most once** per cache miss no matter how many callers race.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration and own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)` which returns `{:ok, value}`. On a cache hit it reads directly from ETS (no GenServer round-trip). On a miss it participates in the single-flight protocol described above and returns `{:ok, value}`. Any term `fallback_fn` produces — including `nil` — is stored and treated as a genuine cached value, so a later fetch of the same key is a hit that does not re-run `fallback_fn`.
- `CacheLayer.invalidate(server, table, key)` which removes the entry for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` which removes **all** cached entries for the given `table`. Returns `:ok`.

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. The GenServer coordinates the single-flight bookkeeping (who is the leader for `{table, key}`, which callers are waiting) but must **not** execute `fallback_fn` itself. If the leader crashes before producing a value, the followers must not hang forever — one of them should get a chance to retry. Because cache hits bypass the GenServer, callers must be able to locate a table's ETS tid without a GenServer call; if you register anything process-global for that lookup (for example `:persistent_term` entries), the server must trap exits and its `terminate/2` must erase every such registration when it stops, so a cleanly stopped cache leaves nothing behind (the ETS tables themselves die with their owner).

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.

## The module with `start_link` missing

```elixir
defmodule CacheLayer do
  @moduledoc """
  An ETS-backed read cache with a single-flight, non-blocking concurrency model.

  Each logical `table` (an atom) maps to a separate `:set`, `:public` ETS table
  owned by this process, created lazily on first use. Cache hits are served
  directly from ETS with no GenServer round-trip.

  ## Single-flight

  The expensive `fallback_fn` runs in the *caller's* process, never inside the
  GenServer, so a slow load for one key does not block loads for other keys.
  For a given `{table, key}`:

    * The first caller to miss becomes the **leader** and runs `fallback_fn`.
    * Concurrent callers become **followers**: their `fetch` call is parked
      inside the GenServer (no reply) until the leader finishes, at which point
      they receive the leader's value. `fallback_fn` is therefore invoked at
      most once per cache miss.

  If the leader crashes before reporting a value (monitored via
  `Process.monitor/1`), all parked followers are told to `:retry`, so they never
  hang — one of them becomes the new leader.
  """

  use GenServer

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  def start_link(opts \\ []) do
    # TODO
  end

  @doc """
  Fetches the value cached under `{table, key}`, computing it on a miss.

  On a cache hit the value is read directly from ETS with no GenServer
  round-trip. On a miss the caller joins the single-flight protocol: exactly one
  racing caller runs `fallback_fn`, the rest wait for and receive its result.
  Always returns `{:ok, value}`.
  """
  @spec fetch(GenServer.server(), atom(), term(), (-> term())) :: {:ok, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        join_and_compute(server, table, key, fallback_fn)

      tid ->
        case :ets.lookup(tid, key) do
          [{^key, value}] -> {:ok, value}
          [] -> join_and_compute(server, table, key, fallback_fn)
        end
    end
  end

  @doc """
  Removes the cached entry for `{table, key}`. Always returns `:ok`.
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end

  @doc """
  Removes every cached entry for `table`. Always returns `:ok`.
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end

  # Single-flight participation. Runs the fallback in THIS process when elected
  # leader; blocks (via a parked GenServer call) when a follower.
  defp join_and_compute(server, table, key, fallback_fn) do
    case GenServer.call(server, {:join, table, key}, :infinity) do
      {:hit, value} ->
        {:ok, value}

      {:value, value} ->
        # A follower whose leader completed.
        {:ok, value}

      :retry ->
        # Leader failed; try again (we may become the new leader).
        join_and_compute(server, table, key, fallback_fn)

      {:leader, _ref} ->
        try do
          value = fallback_fn.()
          :ok = GenServer.call(server, {:done, table, key, value}, :infinity)
          {:ok, value}
        rescue
          e ->
            GenServer.call(server, {:fail, table, key}, :infinity)
            reraise e, __STACKTRACE__
        end
    end
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}, inflight: %{}}}
  end

  @impl GenServer
  def handle_call({:join, table, key}, from, state) do
    {tid, state} = ensure_table(table, state)

    case :ets.lookup(tid, key) do
      [{^key, value}] ->
        {:reply, {:hit, value}, state}

      [] ->
        flight_key = {table, key}

        case Map.get(state.inflight, flight_key) do
          nil ->
            leader = elem(from, 0)
            mref = Process.monitor(leader)
            entry = %{leader: leader, mref: mref, waiters: []}
            inflight = Map.put(state.inflight, flight_key, entry)
            {:reply, {:leader, mref}, %{state | inflight: inflight}}

          entry ->
            entry = %{entry | waiters: [from | entry.waiters]}
            {:noreply, %{state | inflight: Map.put(state.inflight, flight_key, entry)}}
        end
    end
  end

  def handle_call({:done, table, key, value}, _from, state) do
    {tid, state} = ensure_table(table, state)
    :ets.insert(tid, {key, value})

    flight_key = {table, key}

    case Map.pop(state.inflight, flight_key) do
      {nil, _} ->
        {:reply, :ok, state}

      {entry, inflight} ->
        Process.demonitor(entry.mref, [:flush])
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, {:value, value}) end)
        {:reply, :ok, %{state | inflight: inflight}}
    end
  end

  def handle_call({:fail, table, key}, _from, state) do
    flight_key = {table, key}

    case Map.pop(state.inflight, flight_key) do
      {nil, _} ->
        {:reply, :ok, state}

      {entry, inflight} ->
        Process.demonitor(entry.mref, [:flush])
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, :retry) end)
        {:reply, :ok, %{state | inflight: inflight}}
    end
  end

  def handle_call({:invalidate, table, key}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete(tid, key)
    end

    {:reply, :ok, state}
  end

  def handle_call({:invalidate_all, table}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete_all_objects(tid)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, mref, :process, _pid, _reason}, state) do
    case Enum.find(state.inflight, fn {_k, entry} -> entry.mref == mref end) do
      nil ->
        {:noreply, state}

      {flight_key, entry} ->
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, :retry) end)
        {:noreply, %{state | inflight: Map.delete(state.inflight, flight_key)}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    pid = self()

    Enum.each(state.tables, fn {table, tid} ->
      :persistent_term.erase({__MODULE__, pid, table})
      :ets.delete(tid)
    end)

    :ok
  end

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp ensure_table(table, %{tables: tables} = state) do
    case Map.get(tables, table) do
      nil ->
        tid = :ets.new(table, [:set, :public])
        :persistent_term.put({__MODULE__, self(), table}, tid)
        {tid, %{state | tables: Map.put(tables, table, tid)}}

      tid ->
        {tid, state}
    end
  end

  defp resolve_pid!(pid) when is_pid(pid), do: pid

  defp resolve_pid!(name) do
    case GenServer.whereis(name) do
      nil -> raise ArgumentError, "CacheLayer: cannot resolve #{inspect(name)} to a pid"
      pid -> pid
    end
  end
end
```

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
