Implement the public `fetch/4` function — the read-through half of the cache.

`fetch(server, table, key, loader_fn)` must serve a cache hit directly from ETS
without a GenServer round-trip, and fall back to the GenServer only when it
cannot serve the value itself. Concretely:

- First resolve `server` to a concrete pid using `resolve_pid!/1`.
- Look up the table's ETS table id via
  `:persistent_term.get({__MODULE__, pid, table}, :no_table)`, using `:no_table`
  as the default so a not-yet-created table is detected.
- If the table does not exist yet (`:no_table`), the entry cannot be cached, so
  delegate to the GenServer with `GenServer.call(server, {:fetch, table, key, loader_fn})`.
- If the table exists (`tid`), look the key up with `:ets.lookup(tid, key)`. On a
  hit (`[{^key, value}]`) return `{:ok, value}` read straight from ETS. On a miss
  (`[]`) delegate to the GenServer with the same
  `GenServer.call(server, {:fetch, table, key, loader_fn})` so the load is
  serialised and `loader_fn` runs at most once.

The GenServer-side `handle_call({:fetch, ...})` (already implemented) does the
actual read-through fill, so `fetch/4` only needs the fast ETS path plus the
delegation fallbacks.

```elixir
defmodule CacheLayer do
  @moduledoc """
  A true write-through cache implemented as a GenServer, backed by ETS.

  Reads are read-through (a miss calls a `loader_fn`, caches, and returns the
  value). Writes and deletes are *write-through*: the caller-supplied store
  function runs first, and the cache is only mutated when that store operation
  succeeds. This guarantees the cache is never ahead of the backing store — a
  failed `put`/`delete` leaves the previously cached value exactly as it was.

  Each logical `table` (an atom) maps to a separate `:set`, `:public` ETS table
  owned by this process, created lazily on first use. Cached reads are served
  directly from ETS; all loads, writes, and deletes are serialised through the
  GenServer so the store functions and the cache never race, and a `loader_fn`
  runs at most once per miss even under concurrency.

  `invalidate/3` and `invalidate_all/2` are cache-only operations: they evict
  from ETS without touching the backing store.
  """

  use GenServer

  @typedoc "A zero-arity store function returning a success/error tuple."
  @type store_fun :: (-> :ok | {:ok, term()} | {:error, term()})

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the cache GenServer.

  Accepts the standard GenServer options, notably `:name` for process
  registration. The started process owns the lifecycle of every ETS table it
  creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Read-through fetch for `{table, key}`.

  On a cache hit the value is read directly from ETS. On a miss `loader_fn` is
  called at most once, its result is cached, and `{:ok, value}` is returned.
  """
  @spec fetch(GenServer.server(), atom(), term(), (-> term())) :: {:ok, term()}
  def fetch(server, table, key, loader_fn)
      when is_atom(table) and is_function(loader_fn, 0) do
    # TODO
  end

  @doc """
  Write-through put for `{table, key}`.

  `writer_fn` persists to the backing store first. Only when it returns `:ok`
  or `{:ok, term}` is the cache updated to `value` and `{:ok, value}` returned.
  On `{:error, reason}` the cache is left untouched and `{:error, reason}` is
  returned.
  """
  @spec put(GenServer.server(), atom(), term(), term(), store_fun()) ::
          {:ok, term()} | {:error, term()}
  def put(server, table, key, value, writer_fn)
      when is_atom(table) and is_function(writer_fn, 0) do
    GenServer.call(server, {:put, table, key, value, writer_fn})
  end

  @doc """
  Delete-through for `{table, key}`.

  `deleter_fn` removes the key from the backing store first. Only when it
  returns `:ok` or `{:ok, term}` is the cache entry removed and `:ok` returned.
  On `{:error, reason}` the cache is left untouched and `{:error, reason}` is
  returned.
  """
  @spec delete(GenServer.server(), atom(), term(), store_fun()) ::
          :ok | {:error, term()}
  def delete(server, table, key, deleter_fn)
      when is_atom(table) and is_function(deleter_fn, 0) do
    GenServer.call(server, {:delete, table, key, deleter_fn})
  end

  @doc """
  Cache-only eviction of `{table, key}`.

  Removes the cached entry without touching the backing store. Always `:ok`.
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end

  @doc """
  Cache-only eviction of every entry for `table`.

  Clears the table's cache without touching the backing store. Always `:ok`.
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
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, loader_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    value =
      case :ets.lookup(tid, key) do
        [{^key, cached}] ->
          cached

        [] ->
          fresh = loader_fn.()
          :ets.insert(tid, {key, fresh})
          fresh
      end

    {:reply, {:ok, value}, state}
  end

  def handle_call({:put, table, key, value, writer_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    reply =
      case writer_fn.() do
        :ok ->
          :ets.insert(tid, {key, value})
          {:ok, value}

        {:ok, _} ->
          :ets.insert(tid, {key, value})
          {:ok, value}

        {:error, reason} ->
          # Store write failed: cache is left exactly as it was.
          {:error, reason}

        other ->
          raise ArgumentError,
                "writer_fn must return :ok, {:ok, term} or " <>
                  "{:error, reason}, got: #{inspect(other)}"
      end

    {:reply, reply, state}
  end

  def handle_call({:delete, table, key, deleter_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    reply =
      case deleter_fn.() do
        :ok ->
          :ets.delete(tid, key)
          :ok

        {:ok, _} ->
          :ets.delete(tid, key)
          :ok

        {:error, reason} ->
          {:error, reason}

        other ->
          raise ArgumentError,
                "deleter_fn must return :ok, {:ok, term} or " <>
                  "{:error, reason}, got: #{inspect(other)}"
      end

    {:reply, reply, state}
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