Implement the GenServer `handle_call/3` callback for the `CacheLayer` module below.
It coordinates the single-flight bookkeeping but must **never** run `fallback_fn` itself.
There are six call clauses to implement:

- **`{:join, table, key}`** — the entry point of the single-flight protocol. First
  ensure the ETS table for `table` exists (via `ensure_table/2`), then look up `key`.
  If the key is present, reply immediately with `{:hit, value}`. Otherwise, consult the
  `inflight` map under the composite key `{table, key}`:
  - If there is no in-flight entry, the caller becomes the **leader**: monitor the
    caller process (the pid from `from`) with `Process.monitor/1`, record a new entry
    `%{leader: leader, mref: mref, waiters: []}` in `inflight`, and reply `{:leader, mref}`.
  - If an entry already exists, the caller is a **follower**: prepend `from` to that
    entry's `waiters` list and **do not reply** (`:noreply`) — the caller stays parked
    until the leader finishes.

- **`{:done, table, key, value}`** — the leader reporting success. Ensure the table
  exists, insert `{key, value}` into ETS, then pop the `{table, key}` entry from
  `inflight`. If there was no entry, just reply `:ok`. Otherwise demonitor the leader
  (`Process.demonitor(mref, [:flush])`), reply `{:value, value}` to every parked waiter
  via `GenServer.reply/2`, drop the entry, and reply `:ok`.

- **`{:fail, table, key}`** — the leader reporting failure. Pop the `{table, key}` entry
  from `inflight`. If none, reply `:ok`. Otherwise demonitor the leader, reply `:retry`
  to every parked waiter so one of them can become the new leader, drop the entry, and
  reply `:ok`.

- **`{:invalidate, table, key}`** — if the table exists, delete `key` from it; then
  reply `:ok`.

- **`{:invalidate_all, table}`** — if the table exists, delete all objects from it; then
  reply `:ok`.

In every case the reply and the (possibly updated) state must be returned in the proper
GenServer `handle_call/3` tuple form.

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

  def handle_call({:join, table, key}, from, state) do
    # TODO
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