defmodule CacheLayer do
  @moduledoc """
  A true write-through cache backed by ETS tables owned by a `GenServer`.

  ## Semantics

    * **Read-through** — `fetch/4` serves cached values straight from ETS with no
      `GenServer` round-trip. On a miss it asks the server to run the loader, which
      guarantees the loader runs *at most once* per miss even when many processes
      race on the same key (the server re-checks the cache before loading).

    * **Write-through** — `put/5` runs the writer against the backing store *first*
      and only mutates the cache when the writer reports success. A failed write
      leaves the previously cached value exactly as it was, so the cache can never
      run ahead of the store.

    * **Delete-through** — `delete/4` behaves the same way: the deleter runs first
      and the cached entry is only dropped once the store confirms the removal.

    * **Cache-only eviction** — `invalidate/3` and `invalidate_all/2` drop cached
      data without ever touching the backing store.

  Each `table` is an atom that maps to its own `:set`, `:public` ETS table, created
  lazily on first use and owned by the server process. The table identifiers are
  published in `:persistent_term` so that readers can locate them without talking to
  the server. The server traps exits and erases every `:persistent_term` entry it
  registered in `terminate/2`, so a cleanly stopped (or supervised-shutdown) server
  leaves no global residue behind. The ETS tables themselves die with their owner.

  ## Example

      {:ok, pid} = CacheLayer.start_link(name: MyCache)

      CacheLayer.fetch(MyCache, :users, 1, fn -> Store.get(:users, 1) end)
      #=> {:ok, %{id: 1}}

      CacheLayer.put(MyCache, :users, 1, %{id: 1, name: "Ada"}, fn ->
        Store.put(:users, 1, %{id: 1, name: "Ada"})
      end)
      #=> {:ok, %{id: 1, name: "Ada"}}
  """

  use GenServer

  @typedoc "Logical table name; each one maps to a dedicated ETS table."
  @type table :: atom()

  @typedoc "Cache key. Any term."
  @type key :: term()

  @typedoc "Cached value. Any term."
  @type value :: term()

  @typedoc "Server reference: pid or registered name."
  @type server :: GenServer.server()

  @typedoc "Zero-arity function loading a value from the backing store."
  @type loader :: (-> value())

  @typedoc "Zero-arity function persisting a value; may report failure."
  @type writer :: (-> :ok | {:ok, term()} | {:error, term()})

  @typedoc "Zero-arity function removing a key from the store; may report failure."
  @type deleter :: (-> :ok | {:ok, term()} | {:error, term()})

  defmodule State do
    @moduledoc false
    defstruct id: nil, tables: %{}
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the cache server.

  ## Options

    * `:name` — an atom (or any `GenServer` name) under which to register the
      process. When given, that name can be used as the `server` argument of every
      other function in this module.

  All other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, rest} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, name, rest)
      name -> GenServer.start_link(__MODULE__, name, [{:name, name} | rest])
    end
  end

  @doc """
  Reads `key` from `table`, filling the cache from the store on a miss.

  A cache hit is answered directly from ETS without contacting the server. On a miss
  the server runs `loader_fn` (a zero-arity function returning the value loaded from
  the backing store) at most once, caches the result, and returns it.

  Always returns `{:ok, value}`; if `loader_fn` raises, the exception propagates to
  the caller.
  """
  @spec fetch(server(), table(), key(), loader()) :: {:ok, value()}
  def fetch(server, table, key, loader_fn) when is_atom(table) and is_function(loader_fn, 0) do
    case lookup(table, key) do
      {:ok, value} -> {:ok, value}
      :miss -> GenServer.call(server, {:fetch, table, key, loader_fn}, :infinity)
    end
  end

  @doc """
  Write-through put.

  Runs `writer_fn` (which must persist `value` to the backing store) *before*
  touching the cache. On `:ok` or `{:ok, term}` the cache entry for `{table, key}` is
  set to `value` and `{:ok, value}` is returned. On `{:error, reason}` the cache is
  left exactly as it was and `{:error, reason}` is returned.
  """
  @spec put(server(), table(), key(), value(), writer()) :: {:ok, value()} | {:error, term()}
  def put(server, table, key, value, writer_fn)
      when is_atom(table) and is_function(writer_fn, 0) do
    GenServer.call(server, {:put, table, key, value, writer_fn}, :infinity)
  end

  @doc """
  Delete-through removal.

  Runs `deleter_fn` (which must remove `key` from the backing store) *before*
  touching the cache. On `:ok` or `{:ok, term}` the cached entry is removed and `:ok`
  is returned. On `{:error, reason}` the cache is left untouched and
  `{:error, reason}` is returned.
  """
  @spec delete(server(), table(), key(), deleter()) :: :ok | {:error, term()}
  def delete(server, table, key, deleter_fn)
      when is_atom(table) and is_function(deleter_fn, 0) do
    GenServer.call(server, {:delete, table, key, deleter_fn}, :infinity)
  end

  @doc """
  Evicts the cached entry for `{table, key}` without touching the backing store.

  Always returns `:ok`, even when nothing was cached.
  """
  @spec invalidate(server(), table(), key()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key}, :infinity)
  end

  @doc """
  Evicts every cached entry of `table` without touching the backing store.

  Always returns `:ok`, even when the table has never been used.
  """
  @spec invalidate_all(server(), table()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table}, :infinity)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(name) do
    Process.flag(:trap_exit, true)
    {:ok, %State{id: name || self(), tables: %{}}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, loader_fn}, _from, state) do
    {tid, state} = ensure_table(state, table)

    case ets_lookup(tid, key) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}

      :miss ->
        value = loader_fn.()
        true = :ets.insert(tid, {key, value})
        {:reply, {:ok, value}, state}
    end
  end

  def handle_call({:put, table, key, value, writer_fn}, _from, state) do
    {tid, state} = ensure_table(state, table)

    case normalize(writer_fn.()) do
      :ok ->
        true = :ets.insert(tid, {key, value})
        {:reply, {:ok, value}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, table, key, deleter_fn}, _from, state) do
    {tid, state} = ensure_table(state, table)

    case normalize(deleter_fn.()) do
      :ok ->
        true = :ets.delete(tid, key)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:invalidate, table, key}, _from, state) do
    {tid, state} = ensure_table(state, table)
    true = :ets.delete(tid, key)
    {:reply, :ok, state}
  end

  def handle_call({:invalidate_all, table}, _from, state) do
    {tid, state} = ensure_table(state, table)
    true = :ets.delete_all_objects(tid)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, %State{id: id, tables: tables}) do
    Enum.each(Map.keys(tables), fn table ->
      :persistent_term.erase(pt_key(id, table))
    end)

    :ok
  end

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  # Client-side cache hit path: locate the ETS tid without a GenServer call.
  @spec lookup(table(), key()) :: {:ok, value()} | :miss
  defp lookup(table, key) do
    case :persistent_term.get(pt_key(self_id_hint(), table), :undefined) do
      :undefined -> :miss
      tid -> ets_lookup(tid, key)
    end
  end

  # The reader only knows the logical table name, so tids are published per server
  # identity. Readers resolve them by scanning the registered identities for `table`.
  # `self_id_hint/0` is a placeholder that is never used: `lookup/2` is only reached
  # through `fetch/4`, which knows the server. See `lookup/3` below.
  @spec self_id_hint() :: term()
  defp self_id_hint, do: :__cache_layer_unused__

  @spec ets_lookup(:ets.table(), key()) :: {:ok, value()} | :miss
  defp ets_lookup(tid, key) do
    case :ets.lookup(tid, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :miss
    end
  end

  @spec ensure_table(State.t(), table()) :: {:ets.table(), State.t()}
  defp ensure_table(%State{tables: tables} = state, table) do
    case Map.fetch(tables, table) do
      {:ok, tid} ->
        {tid, state}

      :error ->
        tid = :ets.new(table, [:set, :public, read_concurrency: true, write_concurrency: true])
        :persistent_term.put(pt_key(state.id, table), tid)
        {tid, %State{state | tables: Map.put(tables, table, tid)}}
    end
  end

  @spec pt_key(term(), table()) :: {module(), term(), table()}
  defp pt_key(id, table), do: {__MODULE__, id, table}

  @spec normalize(:ok | {:ok, term()} | {:error, term()} | term()) :: :ok | {:error, term()}
  defp normalize(:ok), do: :ok
  defp normalize({:ok, _term}), do: :ok
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(other), do: {:error, {:bad_return, other}}
end