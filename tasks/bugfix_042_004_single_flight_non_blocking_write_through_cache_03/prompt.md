# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# `CacheLayer` — ETS-backed read-through cache with single-flight, non-blocking loads

Implement an Elixir module `CacheLayer` that wraps database reads with an ETS-backed cache using a **single-flight (request-coalescing), non-blocking** concurrency model. Deliver the complete module in a single file.

**Concurrency model (the point of the ticket)**
- The naive design serialises *every* cache miss through the GenServer and runs the slow `fallback_fn` inside the GenServer's critical section, so one slow database call blocks misses for **all** keys. That is not acceptable here.
- The expensive `fallback_fn` must run **outside** the GenServer process, so a slow load for one key never blocks loads for other keys — distinct keys are computed concurrently.
- For a single key, when several callers miss at the same time, exactly **one** of them (the "leader") runs `fallback_fn`; the others ("followers") block until the leader finishes and then receive the leader's result.
- `fallback_fn` is called **at most once** per cache miss no matter how many callers race.
- If the leader crashes before producing a value, followers must not hang forever — one of them should get a chance to retry.

**Public API**
- `CacheLayer.start_link(opts)` — starts the process as a GenServer. Accepts a `:name` option for process registration. Owns the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)` — returns `{:ok, value}`.
  - Cache hit: reads directly from ETS, no GenServer round-trip.
  - Cache miss: participates in the single-flight protocol above, returns `{:ok, value}`.
  - Any term `fallback_fn` produces — including `nil` — is stored and treated as a genuine cached value, so a later fetch of the same key is a hit that does not re-run `fallback_fn`.
- `CacheLayer.invalidate(server, table, key)` — removes the entry for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` — removes **all** cached entries for the given `table`. Returns `:ok`.

**Table management**
- Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer.
- Tables are created lazily on first use.

**GenServer responsibilities**
- Coordinates the single-flight bookkeeping: who is the leader for `{table, key}`, which callers are waiting.
- Must **not** execute `fallback_fn` itself.

**Table lookup and cleanup**
- Because cache hits bypass the GenServer, callers must be able to locate a table's ETS tid without a GenServer call.
- If anything process-global is registered for that lookup (for example `:persistent_term` entries), the server must trap exits and its `terminate/2` must erase every such registration when it stops, so a cleanly stopped cache leaves nothing behind. The ETS tables themselves die with their owner.

**Constraints**
- Single file, complete module.
- OTP and the standard library only; no external dependencies.

## The buggy module

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

  @doc """
  Starts the cache as a GenServer.

  Accepts the usual GenServer options, notably `:name` for process registration.
  The started process owns the lifecycle of every ETS table it creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
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
            leader = elem(from, 1)
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

## Failing test report

```
12 of 13 test(s) failed:

  * test cache miss calls the fallback and returns the value
      :exit: {{:badarg, [{:erlang, :monitor, [:process, #Reference<0.1455490433.105119745.123985>], [error_info: %{module: :erl_erts_errors}]}, {CacheLayer, :handle_call, 3, [file: ~c".gen_staging/bugfix_042_004_single_flight_non_blocking_write_through_cache_03_mutant.ex", line: 136]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]},

  * test cache hit does not call the fallback again
      :exit: {{:badarg, [{:erlang, :monitor, [:process, #Reference<0.1455490433.105119745.124101>], [error_info: %{module: :erl_erts_errors}]}, {CacheLayer, :handle_call, 3, [file: ~c".gen_staging/bugfix_042_004_single_flight_non_blocking_write_through_cache_03_mutant.ex", line: 136]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]},

  * test nil is a valid cached value and is not recomputed
      :exit: {{:badarg, [{:erlang, :monitor, [:process, #Reference<0.1455490433.105119745.124150>], [error_info: %{module: :erl_erts_errors}]}, {CacheLayer, :handle_call, 3, [file: ~c".gen_staging/bugfix_042_004_single_flight_non_blocking_write_through_cache_03_mutant.ex", line: 136]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]},

  * test concurrent misses of the same key run the fallback exactly once
      {:EXIT, #PID<0.225.0>}: {{:badarg, [{:erlang, :monitor, [:process, #Reference<0.1455490433.105119746.121670>], [error_info: %{module: :erl_erts_errors}]}, {CacheLayer, :handle_call, 3, [file: ~c".gen_staging/bugfix_042_004_single_flight_non_blocking_write_through_cache_03_mutant.ex", line: 136]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl

  (…8 more)
```
