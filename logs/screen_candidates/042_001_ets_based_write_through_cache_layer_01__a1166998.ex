defmodule CacheLayer do
  @moduledoc """
  A write-through cache layer backed by ETS and owned by a single `GenServer`.

  Each logical `table` (an atom) maps to its own ETS table of type `:set`. Tables are created
  lazily, the first time a given table atom is used, and are owned by the `CacheLayer` process,
  so they are torn down automatically when it stops.

  ## Concurrency model

    * **Reads** go straight to ETS from the calling process. The cache-hit path never touches the
      `CacheLayer` process, so it does not serialise readers.
    * **Writes and deletions** are serialised through the `CacheLayer` process.
    * On a cache miss the caller asks the server to populate the entry. The server re-checks ETS
      while holding its (implicit) lock, so the supplied `fallback_fn` is invoked **at most once**
      per miss: concurrent callers racing on the same key queue up, and all but the first observe
      the freshly written value.

  Because `fallback_fn` runs inside the server process, a slow fallback blocks other writes to the
  cache. This is the price of the at-most-once guarantee. Exceptions, throws and exits raised by
  `fallback_fn` are captured and re-raised in the calling process, leaving the server alive.

  ## Example

      {:ok, _pid} = CacheLayer.start_link(name: MyCache)

      {:ok, user} = CacheLayer.fetch(MyCache, :users, 1, fn -> Repo.get(User, 1) end)
      :ok = CacheLayer.invalidate(MyCache, :users, 1)
      :ok = CacheLayer.invalidate_all(MyCache, :users)
  """

  use GenServer

  @type server :: GenServer.server()
  @type table :: atom()
  @type key :: term()
  @type value :: term()

  # --------------------------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------------------------

  @doc """
  Starts the cache process.

  Supported options:

    * `:name` - an optional name used to register the process (any valid `t:GenServer.name/0`).

  All other options are ignored. Returns the usual `GenServer.on_start/0` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, :ok, name: name)
      :error -> GenServer.start_link(__MODULE__, :ok)
    end
  end

  @doc """
  Returns the cached value for `{table, key}`, computing it on a miss.

  On a cache hit the value is read directly from ETS by the calling process. On a miss the call is
  forwarded to `server`, which invokes `fallback_fn` (a zero-arity function, typically a database
  read), stores the result and returns it. `fallback_fn` is called at most once per miss, even if
  many processes miss on the same key concurrently.

  Always returns `{:ok, value}`. If `fallback_fn` raises, throws or exits, the same error is
  re-raised in the calling process and nothing is cached.
  """
  @spec fetch(server(), table(), key(), (-> value())) :: {:ok, value()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    case lookup(server, table, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case GenServer.call(server, {:fetch, table, key, fallback_fn}, :infinity) do
          {:ok, value} -> {:ok, value}
          {:raised, kind, reason, stacktrace} -> :erlang.raise(kind, reason, stacktrace)
        end
    end
  end

  @doc """
  Removes the entry for `{table, key}` from the cache.

  Deleting a key that is not cached, or one belonging to a table that was never created, is a
  no-op. Always returns `:ok`.
  """
  @spec invalidate(server(), table(), key()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key}, :infinity)
  end

  @doc """
  Removes every cached entry for `table`, leaving the (now empty) ETS table in place.

  Invalidating a table that was never created is a no-op. Always returns `:ok`.
  """
  @spec invalidate_all(server(), table()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table}, :infinity)
  end

  # --------------------------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    publish(%{})
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, fallback_fn}, _from, tables) do
    {tid, tables} = ensure_table(table, tables)

    case :ets.lookup(tid, key) do
      [{^key, value}] ->
        {:reply, {:ok, value}, tables}

      [] ->
        case run_fallback(fallback_fn) do
          {:ok, value} ->
            :ets.insert(tid, {key, value})
            {:reply, {:ok, value}, tables}

          {:raised, _kind, _reason, _stacktrace} = failure ->
            {:reply, failure, tables}
        end
    end
  end

  def handle_call({:invalidate, table, key}, _from, tables) do
    case Map.fetch(tables, table) do
      {:ok, tid} -> :ets.delete(tid, key)
      :error -> :ok
    end

    {:reply, :ok, tables}
  end

  def handle_call({:invalidate_all, table}, _from, tables) do
    case Map.fetch(tables, table) do
      {:ok, tid} -> :ets.delete_all_objects(tid)
      :error -> :ok
    end

    {:reply, :ok, tables}
  end

  @impl GenServer
  def terminate(_reason, _tables) do
    :persistent_term.erase(index_key(self()))
    :ok
  end

  # --------------------------------------------------------------------------------------------
  # Internals
  # --------------------------------------------------------------------------------------------

  # Fast path: resolve the owner, look up its table index and read from ETS, all in the caller.
  @spec lookup(server(), table(), key()) :: {:ok, value()} | :error
  defp lookup(server, table, key) do
    with pid when is_pid(pid) <- GenServer.whereis(server),
         %{} = tables <- :persistent_term.get(index_key(pid), nil),
         {:ok, tid} <- Map.fetch(tables, table),
         [{^key, value}] <- :ets.lookup(tid, key) do
      {:ok, value}
    else
      _other -> :error
    end
  end

  @spec ensure_table(table(), %{optional(table()) => :ets.tid()}) ::
          {:ets.tid(), %{optional(table()) => :ets.tid()}}
  defp ensure_table(table, tables) do
    case Map.fetch(tables, table) do
      {:ok, tid} ->
        {tid, tables}

      :error ->
        tid = :ets.new(table, [:set, :public, read_concurrency: true])
        tables = Map.put(tables, table, tid)
        publish(tables)
        {tid, tables}
    end
  end

  @spec run_fallback((-> value())) :: {:ok, value()} | {:raised, atom(), term(), Exception.stacktrace()}
  defp run_fallback(fallback_fn) do
    {:ok, fallback_fn.()}
  catch
    kind, reason -> {:raised, kind, reason, __STACKTRACE__}
  end

  @spec publish(%{optional(table()) => :ets.tid()}) :: :ok
  defp publish(tables) do
    :persistent_term.put(index_key(self()), tables)
  end

  @spec index_key(pid()) :: {module(), pid()}
  defp index_key(pid), do: {__MODULE__, pid}
end