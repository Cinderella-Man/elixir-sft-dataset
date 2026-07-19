# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed write-through cache.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration and own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)` which returns the cached value for `{table, key}` if it exists in ETS, or calls `fallback_fn.()` on a cache miss, stores the result in ETS, and returns it. The return value should always be `{:ok, value}`. Whatever `fallback_fn` returns is cached verbatim, so a stored `nil` (or any other falsy term) counts as a genuine cache hit and must **not** trigger a second fallback call on the next fetch.
- `CacheLayer.invalidate(server, table, key)` which removes the entry for `{table, key}` from the cache. Returns `:ok` whether or not the entry existed.
- `CacheLayer.invalidate_all(server, table)` which removes **all** cached entries for the given `table`. Returns `:ok` whether or not the table had any entries.

Each `table` is an atom and should correspond to a separate ETS table owned by the GenServer. Tables should be created lazily on first use (i.e. create the ETS table the first time a given table atom is seen). Use `:set` type ETS tables with public read access so that `fetch` can read directly from ETS without going through the GenServer process, while writes and deletes are serialised through the GenServer.

So that `fetch` can locate a table's ETS tid without a GenServer round-trip, publish the tid to `:persistent_term` under the key `{CacheLayer, server_pid, table}` (where `server_pid` is the GenServer's own pid) when the table is first created. When the GenServer stops, it must erase these `:persistent_term` entries — after `GenServer.stop/1`, `:persistent_term.get({CacheLayer, pid, table})` must no longer return a tid — and the ETS tables it owned must be freed.

The `fallback_fn` is a zero-arity anonymous function that the caller supplies. It will typically query a database. You must guarantee it is called **at most once** per cache miss — do not call it more than once even under concurrent access.

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.

## The module with `init` missing

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

  def init(:ok) do
    # TODO
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

Give me only the complete implementation of `init` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
