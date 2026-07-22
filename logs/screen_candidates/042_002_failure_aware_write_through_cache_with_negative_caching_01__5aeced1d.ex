defmodule CacheLayer do
  @moduledoc """
  A failure-aware, write-through cache over arbitrary data sources, backed by ETS.

  `CacheLayer` sits in front of a fallible data source (a database, a remote service,
  a row that is being rebuilt) and caches *both* outcomes of a read:

    * **Successes** are cached permanently, until explicitly invalidated.
    * **Failures** are cached *negatively* for a bounded number of subsequent reads,
      so a flapping backend is not hammered — but the cache always eventually retries.

  ## Topology

  Every `table` is an atom that maps to its own `:set`, `:public` ETS table, created
  lazily on first use and owned by the `CacheLayer` GenServer. Because tables are
  owned by the process, they are torn down automatically when it terminates.

  ## Concurrency

  Reads that hit a cached success are served directly from ETS with no GenServer
  round-trip. Everything that mutates state — writes, deletes, and negative-hit
  bookkeeping — is serialised through the GenServer, which guarantees that
  `fallback_fn` runs *at most once* per miss even when many processes race on the
  same key.

  ## Negative caching

  The `:negative_hits` option (default `3`) is the number of times a cached failure
  is served before the entry is evicted and the backend retried. Setting it to `0`
  disables negative caching entirely: failures are returned but never cached.

      {:ok, pid} = CacheLayer.start_link(name: MyCache, negative_hits: 2)

      CacheLayer.fetch(MyCache, :users, 1, fn -> {:ok, %{id: 1}} end)
      #=> {:ok, %{id: 1}}          (fallback ran, cached permanently)

      CacheLayer.fetch(MyCache, :users, 2, fn -> {:error, :db_down} end)
      #=> {:error, :db_down}       (fallback ran, cached negatively, budget 2)

      CacheLayer.fetch(MyCache, :users, 2, fn -> raise "never called" end)
      #=> {:error, :db_down}       (served from cache, budget 1)

      CacheLayer.fetch(MyCache, :users, 2, fn -> raise "never called" end)
      #=> {:error, :db_down}       (served from cache, budget 0 -> evicted)

      CacheLayer.fetch(MyCache, :users, 2, fn -> {:ok, :recovered} end)
      #=> {:ok, :recovered}        (fallback retried)
  """

  use GenServer

  @default_negative_hits 3

  @typedoc "Logical cache table name; each maps to its own ETS table."
  @type table :: atom()

  @typedoc "Any term usable as an ETS key."
  @type key :: term()

  @typedoc "A zero-arity function returning `{:ok, value}` or `{:error, reason}`."
  @type fallback :: (-> {:ok, term()} | {:error, term()})

  @typedoc "A running `CacheLayer` process: pid or registered name."
  @type server :: GenServer.server()

  @typedoc "Options accepted by `start_link/1`."
  @type option :: {:name, GenServer.name()} | {:negative_hits, non_neg_integer()}

  # Internal state.
  defstruct tables: %{}, negative_hits: @default_negative_hits

  ## Public API

  @doc """
  Starts a `CacheLayer` process linked to the current process.

  ## Options

    * `:name` — a name to register the process under, as accepted by `GenServer.start_link/3`.
    * `:negative_hits` — a non-negative integer (default `#{@default_negative_hits}`) giving how
      many times a cached failure is served before it is evicted and the fallback retried.
      `0` disables negative caching.

  All ETS tables created by this process are owned by it and destroyed when it exits.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    negative_hits = Keyword.get(opts, :negative_hits, @default_negative_hits)

    unless is_integer(negative_hits) and negative_hits >= 0 do
      raise ArgumentError,
            ":negative_hits must be a non-negative integer, got: #{inspect(negative_hits)}"
    end

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{negative_hits: negative_hits}, gen_opts)
  end

  @doc """
  Fetches the value stored under `key` in `table`, using `fallback_fn` on a miss.

  Behaviour:

    * **Hit, cached success** — returns `{:ok, value}` straight from ETS, without any
      GenServer round-trip and without calling `fallback_fn`.
    * **Hit, cached failure** — returns `{:error, reason}` without calling `fallback_fn`,
      consuming one unit of that entry's negative-hit budget. When the budget is
      exhausted, the entry is evicted so the next `fetch/4` retries the backend.
    * **Miss** — calls `fallback_fn.()` at most once (concurrent callers on the same key
      share the single invocation). `{:ok, value}` is cached permanently; `{:error, reason}`
      is cached negatively, subject to `:negative_hits`.

  Returns whatever the cache or the fallback produced: `{:ok, value}` or `{:error, reason}`.
  """
  @spec fetch(server(), table(), key(), fallback()) :: {:ok, term()} | {:error, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    case lookup_success(table, key) do
      {:ok, value} -> {:ok, value}
      :miss -> GenServer.call(server, {:fetch, table, key, fallback_fn}, :infinity)
    end
  end

  @doc """
  Removes the cached entry — success or failure — stored under `key` in `table`.

  Always returns `:ok`, whether or not an entry existed. Unknown tables are a no-op.
  """
  @spec invalidate(server(), table(), key()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key}, :infinity)
  end

  @doc """
  Removes every cached entry — successes and failures — for `table`.

  The underlying ETS table is kept (emptied), so subsequent reads simply miss.
  Always returns `:ok`; unknown tables are a no-op.
  """
  @spec invalidate_all(server(), table()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table}, :infinity)
  end

  ## GenServer callbacks

  @impl GenServer
  def init(%{negative_hits: negative_hits}) do
    Process.flag(:trap_exit, true)
    {:ok, %__MODULE__{negative_hits: negative_hits}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    state = ensure_table(state, table)
    tid = Map.fetch!(state.tables, table)

    case :ets.lookup(tid, key) do
      [{^key, {:ok, value}}] ->
        # Another caller populated it while we were queued.
        {:reply, {:ok, value}, state}

      [{^key, {:error, reason}, remaining}] ->
        {:reply, {:error, reason}, serve_negative(tid, key, reason, remaining)}
        |> put_state(state)

      [] ->
        run_fallback(tid, key, fallback_fn, state)
    end
  end

  def handle_call({:invalidate, table, key}, _from, state) do
    case Map.fetch(state.tables, table) do
      {:ok, tid} -> :ets.delete(tid, key)
      :error -> :ok
    end

    {:reply, :ok, state}
  end

  def handle_call({:invalidate_all, table}, _from, state) do
    case Map.fetch(state.tables, table) do
      {:ok, tid} -> :ets.delete_all_objects(tid)
      :error -> :ok
    end

    {:reply, :ok, state}
  end

  ## Internal helpers

  # Direct, lock-free ETS read for the fast path. Only cached successes are served here;
  # cached failures must go through the GenServer so the negative-hit budget is accounted
  # for exactly once, even under concurrent readers.
  @spec lookup_success(table(), key()) :: {:ok, term()} | :miss
  defp lookup_success(table, key) do
    case :ets.lookup(table, key) do
      [{^key, {:ok, value}}] -> {:ok, value}
      _other -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @spec ensure_table(%__MODULE__{}, table()) :: %__MODULE__{}
  defp ensure_table(%__MODULE__{tables: tables} = state, table) do
    if Map.has_key?(tables, table) do
      state
    else
      tid = :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
      %__MODULE__{state | tables: Map.put(tables, table, tid)}
    end
  end

  @spec run_fallback(:ets.tid() | atom(), key(), fallback(), %__MODULE__{}) ::
          {:reply, {:ok, term()} | {:error, term()}, %__MODULE__{}}
  defp run_fallback(tid, key, fallback_fn, state) do
    case fallback_fn.() do
      {:ok, value} ->
        :ets.insert(tid, {key, {:ok, value}})
        {:reply, {:ok, value}, state}

      {:error, reason} ->
        cache_failure(tid, key, reason, state.negative_hits)
        {:reply, {:error, reason}, state}

      other ->
        raise ArgumentError,
              "fallback must return {:ok, value} or {:error, reason}, got: #{inspect(other)}"
    end
  end

  # With a budget of 0, failures are never cached at all.
  @spec cache_failure(:ets.tid() | atom(), key(), term(), non_neg_integer()) :: :ok
  defp cache_failure(_tid, _key, _reason, 0), do: :ok

  defp cache_failure(tid, key, reason, budget) do
    :ets.insert(tid, {key, {:error, reason}, budget})
    :ok
  end

  # A cached failure has just been served: burn one unit of budget, evicting at zero
  # so the next fetch retries the backend.
  @spec serve_negative(:ets.tid() | atom(), key(), term(), pos_integer()) :: :ok
  defp serve_negative(tid, key, _reason, remaining) when remaining <= 1 do
    :ets.delete(tid, key)
    :ok
  end

  defp serve_negative(tid, key, reason, remaining) do
    :ets.insert(tid, {key, {:error, reason}, remaining - 1})
    :ok
  end

  # Discards the `:ok` from the bookkeeping helper and restores the real state term.
  @spec put_state({:reply, term(), :ok}, %__MODULE__{}) :: {:reply, term(), %__MODULE__{}}
  defp put_state({:reply, reply, :ok}, state), do: {:reply, reply, state}
end