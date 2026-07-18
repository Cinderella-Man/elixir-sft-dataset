# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule CacheLayer do
  @moduledoc """
  An ETS-backed write-through cache implemented as a GenServer.

  ## Design

  Each logical `table` (an atom) maps to a **separate** ETS table owned by this
  process. Tables are created lazily the first time a given atom is seen.

  The ETS tables are created with `[:set, :public]` so callers can read values
  directly from ETS without any GenServer round-trip. All writes and deletes are
  serialised through the GenServer so that `fallback_fn` is invoked **at most
  once** per cache miss even under heavy concurrent load (the GenServer
  re-checks ETS before calling the fallback).

  ## Locating ETS tables without a GenServer call

  When a `CacheLayer` creates a new ETS table it advertises the tid via
  `:persistent_term` under the key `{CacheLayer, server_pid, table_atom}`.
  `fetch/4` reads that term first (O(1), no copying for the reference itself)
  and then hits ETS directly on a cache hit, so the happy path never touches
  the GenServer mailbox.
  """

  use GenServer

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the `CacheLayer` GenServer and links it to the calling process.

  ## Options

  Accepts any option understood by `GenServer.start_link/3`. In practice the
  most useful one is:

    * `:name` – registers the process under the given name so callers can
      reference it by atom instead of by pid.

  ## Examples

      {:ok, pid} = CacheLayer.start_link()
      {:ok, _}   = CacheLayer.start_link(name: :my_cache)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Returns `{:ok, value}` for the cached `{table, key}` pair.

  ### Cache hit (fast path)
  The value is read directly from the ETS table — no GenServer round-trip.

  ### Cache miss (slow path)
  The call is forwarded to the GenServer, which:

  1. Re-checks the ETS table (a concurrent caller may have just populated the
     entry).
  2. If the entry is still absent, calls `fallback_fn.()` **exactly once**,
     stores the result in ETS, and returns it.

  `fallback_fn` must be a zero-arity anonymous function. It is guaranteed to be
  called at most once per cache miss regardless of concurrent callers.

  ## Examples

      CacheLayer.fetch(:my_cache, :users, 42, fn -> DB.get_user(42) end)
      #=> {:ok, %User{id: 42, ...}}
  """
  @spec fetch(GenServer.server(), atom(), term(), (-> term())) :: {:ok, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        # Table has not been created yet; let the GenServer handle everything,
        # including table creation.
        GenServer.call(server, {:fetch, table, key, fallback_fn})

      tid ->
        # Table exists — try a direct ETS read (no GenServer involved).
        case :ets.lookup(tid, key) do
          [{^key, value}] ->
            {:ok, value}

          [] ->
            # Cache miss: serialise through the GenServer so only one caller
            # runs the fallback.
            GenServer.call(server, {:fetch, table, key, fallback_fn})
        end
    end
  end

  @doc """
  Removes the cached entry for `{table, key}`.

  Returns `:ok` whether or not the entry existed.

  ## Examples

      :ok = CacheLayer.invalidate(:my_cache, :users, 42)
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end

  @doc """
  Removes **all** cached entries for `table`.

  The ETS table itself is kept alive for future use; only its contents are
  cleared.

  Returns `:ok` whether or not the table had any entries.

  ## Examples

      :ok = CacheLayer.invalidate_all(:my_cache, :users)
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    # Trap exits so `terminate/2` is reliably called, giving us a chance to
    # clean up :persistent_term entries even if the supervisor shuts us down.
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}}}
  end

  @impl GenServer
  # Fetch — serialised write path (also handles first-time table creation).
  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    # Re-check ETS before invoking the fallback: a concurrent caller that also
    # missed the cache and ended up here first may have already populated it.
    value =
      case :ets.lookup(tid, key) do
        [{^key, cached}] ->
          cached

        [] ->
          fresh = fallback_fn.()
          :ets.insert(tid, {key, fresh})
          fresh
      end

    {:reply, {:ok, value}, state}
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
  def terminate(_reason, state) do
    pid = self()

    # Delete each ETS table (which also frees its memory) and remove the
    # corresponding :persistent_term entry so stale tids cannot leak to callers
    # that somehow still hold a reference to this (now-dead) server.
    Enum.each(state.tables, fn {table, tid} ->
      :persistent_term.erase({__MODULE__, pid, table})
      :ets.delete(tid)
    end)

    :ok
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  # Returns the tid for `table`, creating the ETS table if this is the first
  # time we have seen this atom. Publishing via :persistent_term is done here
  # so `fetch/4` can find the tid on the next call without hitting the GenServer.
  defp ensure_table(table, %{tables: tables} = state) do
    case Map.get(tables, table) do
      nil ->
        # Named tables would collide if multiple CacheLayer instances use the
        # same atom, so we use unnamed tables and track tids ourselves.
        tid = :ets.new(table, [:set, :public])

        # Publish so fetch/4 can bypass the GenServer on future cache hits.
        :persistent_term.put({__MODULE__, self(), table}, tid)

        new_state = %{state | tables: Map.put(tables, table, tid)}
        {tid, new_state}

      tid ->
        {tid, state}
    end
  end

  # Resolve any valid GenServer.server() reference to a concrete pid.
  defp resolve_pid!(pid) when is_pid(pid), do: pid

  defp resolve_pid!(name) do
    case GenServer.whereis(name) do
      nil -> raise ArgumentError, "CacheLayer: cannot resolve #{inspect(name)} to a pid"
      pid -> pid
    end
  end
end
```

## New specification

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
