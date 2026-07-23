# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# `CacheLayer` — True Write-Through Cache with Backing-Store Propagation

## Overview

`CacheLayer` is a single Elixir module implementing a **true write-through cache**. Reads are served from an ETS cache with read-through fill. Writes and deletes are propagated to a backing store *before* the cache is updated, so the cache is never ahead of the store.

The deliverable is the complete module in a single file, built on OTP and the standard library only, with no external dependencies.

## API

The module exposes the following public functions.

### `CacheLayer.start_link(opts)`

Starts the process as a GenServer. It accepts a `:name` option for process registration and owns the lifecycle of all ETS tables it creates.

### `CacheLayer.fetch(server, table, key, loader_fn)`

Read-through. If `{table, key}` is cached, the function returns `{:ok, value}`, read directly from ETS. On a miss it calls `loader_fn.()` — a zero-arity function that loads from the store and returns the value — **at most once**, caches the result, and returns `{:ok, value}`.

### `CacheLayer.put(server, table, key, value, writer_fn)`

Write-through. `writer_fn` is a zero-arity function that persists the value to the backing store and returns `:ok`, `{:ok, term}`, or `{:error, reason}`. `writer_fn.()` is called first; **only if it succeeds** is the cache updated to `value` and `{:ok, value}` returned. If it returns `{:error, reason}`, the cache is left untouched and `{:error, reason}` is returned.

### `CacheLayer.delete(server, table, key, deleter_fn)`

Delete-through. `deleter_fn` is a zero-arity function that removes the key from the backing store and returns `:ok`, `{:ok, term}`, or `{:error, reason}`. It is called first; **only if it succeeds** is the entry removed from the cache and `:ok` returned. On `{:error, reason}`, the cache is left untouched and `{:error, reason}` is returned.

### `CacheLayer.invalidate(server, table, key)`

Cache-only eviction. Removes the cached entry **without touching the backing store**. Returns `:ok`.

### `CacheLayer.invalidate_all(server, table)`

Cache-only eviction of **all** entries for the table, leaving the store untouched. Returns `:ok`.

## Storage and concurrency model

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. Cached reads must be servable directly from ETS without a GenServer round-trip. All loads, writes, and deletes are serialised through the GenServer so that the store functions and the cache never race.

## Edge cases and consistency guarantees

- The key consistency rule: the cache is only mutated on a *successful* store operation — a failed `put`/`delete` must leave the previously cached value exactly as it was.
- `loader_fn.()` must be invoked at most once per cache miss.
- Because cached reads bypass the GenServer, callers must be able to locate a table's ETS tid without a GenServer call.
- If anything process-global is registered for that lookup (for example `:persistent_term` entries), the server must trap exits, and its `terminate/2` must erase every such registration when it stops — including a supervised shutdown — so that a cleanly stopped server leaves nothing behind. The ETS tables themselves die with their owner.

## The buggy module

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
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        GenServer.call(server, {:fetch, table, key, loader_fn})

      tid ->
        case :ets.lookup(tid, key) do
          [{^key, value}] -> {:error, value}
          [] -> GenServer.call(server, {:fetch, table, key, loader_fn})
        end
    end
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

## Failing test report

```
8 of 14 test(s) failed:

  * test fetch loads on a miss and caches for later hits
      
      
      match (=) failed
      code:  assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
      left:  {:ok, :v1}
      right: {:error, :v1}
      

  * test put writes through to the store then updates the cache
      
      
      match (=) failed
      code:  assert {:ok, :new} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:from_db) end)
      left:  {:ok, :new}
      right: {:error, :new}
      

  * test put overwrites an existing cached value
      
      
      match (=) failed
      code:  assert {:ok, :updated} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
      left:  {:ok, :updated}
      right: {:error, :updated}
      

  * test a failed write leaves the previously cached value intact
      
      
      match (=) failed
      code:  assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
      left:  {:ok, :v1}
      right: {:error, :v1}
      

  (…4 more)
```
