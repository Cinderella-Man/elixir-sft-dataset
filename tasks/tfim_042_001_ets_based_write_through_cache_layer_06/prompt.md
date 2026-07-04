# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
  @spec fetch(GenServer.server(), atom(), term(), (() -> term())) :: {:ok, term()}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule CacheLayerTest do
  use ExUnit.Case, async: false

  # --- Call-count tracker for mocking the fallback ---

  defmodule CallTracker do
    use Agent

    def start_link(return_val) do
      Agent.start_link(fn -> {0, return_val} end, name: __MODULE__)
    end

    def fallback do
      Agent.update(__MODULE__, fn {count, val} -> {count + 1, val} end)
      Agent.get(__MODULE__, fn {_, val} -> val end)
    end

    def call_count, do: Agent.get(__MODULE__, fn {count, _} -> count end)

    def set_return(val),
      do: Agent.update(__MODULE__, fn {count, _} -> {count, val} end)
  end

  setup do
    start_supervised!({CallTracker, :db_value})

    {:ok, pid} = CacheLayer.start_link([])
    %{cl: pid}
  end

  # -------------------------------------------------------
  # Basic fetch behaviour
  # -------------------------------------------------------

  test "cache miss calls fallback and returns value", %{cl: cl} do
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1
  end

  test "cache hit does not call fallback a second time", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1
  end

  test "fallback return value is correctly stored and returned", %{cl: cl} do
    CallTracker.set_return(%{name: "Alice", age: 30})
    {:ok, first} = CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    {:ok, second} = CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)

    assert first == %{name: "Alice", age: 30}
    assert first == second
    assert CallTracker.call_count() == 1
  end

  # -------------------------------------------------------
  # Invalidate single key
  # -------------------------------------------------------

  test "invalidate removes the key so the next fetch calls fallback again", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1

    :ok = CacheLayer.invalidate(cl, :users, "u:1")

    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end

  test "invalidating a non-existent key returns :ok without error", %{cl: cl} do
    # TODO
  end

  test "invalidate only removes the targeted key, leaving others intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    CacheLayer.invalidate(cl, :users, "u:1")

    # u:2 still cached — no extra fallback call
    CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    # u:1 was evicted — fallback fires again
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 3
  end

  # -------------------------------------------------------
  # Invalidate all keys for a table
  # -------------------------------------------------------

  test "invalidate_all clears every key in the table", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &CallTracker.fallback/0)
    end

    assert CallTracker.call_count() == 5

    :ok = CacheLayer.invalidate_all(cl, :users)

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &CallTracker.fallback/0)
    end

    assert CallTracker.call_count() == 10
  end

  test "invalidate_all on an unused table returns :ok without error", %{cl: cl} do
    assert :ok = CacheLayer.invalidate_all(cl, :never_used_table)
  end

  # -------------------------------------------------------
  # Table independence
  # -------------------------------------------------------

  test "different tables are completely independent namespaces", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)

    # Same key, different tables — two misses
    assert CallTracker.call_count() == 2

    # Both should now be cached independently
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end

  test "invalidate_all on one table does not affect another", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    CacheLayer.invalidate_all(cl, :users)

    # posts cache untouched
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    # users cache cleared
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 3
  end

  # -------------------------------------------------------
  # Lazy table creation
  # -------------------------------------------------------

  test "tables are created on demand and can hold any term as value", %{cl: cl} do
    CallTracker.set_return([1, 2, 3])
    assert {:ok, [1, 2, 3]} = CacheLayer.fetch(cl, :lists, "my_list", &CallTracker.fallback/0)

    CallTracker.set_return(nil)
    # nil is a valid cached value — should NOT trigger a second fallback call
    assert {:ok, nil} = CacheLayer.fetch(cl, :nullables, "k", &CallTracker.fallback/0)
    assert {:ok, nil} = CacheLayer.fetch(cl, :nullables, "k", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end
end
```
