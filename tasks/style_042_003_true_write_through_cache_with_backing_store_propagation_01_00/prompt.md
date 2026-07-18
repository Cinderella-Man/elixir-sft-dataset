# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `CacheLayer` that is a **true write-through cache**: reads are served from an ETS cache with read-through fill, and writes and deletes are propagated to a backing store *before* the cache is updated, so the cache is never ahead of the store.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration and own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, loader_fn)` — read-through. If `{table, key}` is cached, return `{:ok, value}` (read directly from ETS). On a miss, call `loader_fn.()` (a zero-arity function that loads from the store and returns the value) **at most once**, cache the result, and return `{:ok, value}`.
- `CacheLayer.put(server, table, key, value, writer_fn)` — write-through. `writer_fn` is a zero-arity function that persists the value to the backing store and returns `:ok`, `{:ok, term}`, or `{:error, reason}`. Call `writer_fn.()` first; **only if it succeeds** update the cache to `value` and return `{:ok, value}`. If it returns `{:error, reason}`, leave the cache untouched and return `{:error, reason}`.
- `CacheLayer.delete(server, table, key, deleter_fn)` — delete-through. `deleter_fn` is a zero-arity function that removes the key from the backing store and returns `:ok`, `{:ok, term}`, or `{:error, reason}`. Call it first; **only if it succeeds** remove the entry from the cache and return `:ok`. On `{:error, reason}`, leave the cache untouched and return `{:error, reason}`.
- `CacheLayer.invalidate(server, table, key)` — cache-only eviction. Removes the cached entry **without touching the backing store**. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` — cache-only eviction of **all** entries for the table (store untouched). Returns `:ok`.

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. Cached reads must be servable directly from ETS without a GenServer round-trip; all loads, writes, and deletes are serialised through the GenServer so the store functions and the cache never race. The key consistency rule: the cache is only mutated on a *successful* store operation — a failed `put`/`delete` must leave the previously cached value exactly as it was.

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec fetch(GenServer.server(), atom(), term(), (-> term())) :: {:ok, term()}
  def fetch(server, table, key, loader_fn)
      when is_atom(table) and is_function(loader_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        GenServer.call(server, {:fetch, table, key, loader_fn})

      tid ->
        case :ets.lookup(tid, key) do
          [{^key, value}] -> {:ok, value}
          [] -> GenServer.call(server, {:fetch, table, key, loader_fn})
        end
    end
  end

  @spec put(GenServer.server(), atom(), term(), term(), (-> :ok | {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def put(server, table, key, value, writer_fn)
      when is_atom(table) and is_function(writer_fn, 0) do
    GenServer.call(server, {:put, table, key, value, writer_fn})
  end

  @spec delete(GenServer.server(), atom(), term(), (-> :ok | {:ok, term()} | {:error, term()})) ::
          :ok | {:error, term()}
  def delete(server, table, key, deleter_fn)
      when is_atom(table) and is_function(deleter_fn, 0) do
    GenServer.call(server, {:delete, table, key, deleter_fn})
  end

  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end

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
                "writer_fn must return :ok, {:ok, term} or {:error, reason}, got: #{inspect(other)}"
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
                "deleter_fn must return :ok, {:ok, term} or {:error, reason}, got: #{inspect(other)}"
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

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function; 3 line(s) over 98 columns — wrap them. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/042_003_true_write_through_cache_with_backing_store_propagation_01/attempt_0 -->
