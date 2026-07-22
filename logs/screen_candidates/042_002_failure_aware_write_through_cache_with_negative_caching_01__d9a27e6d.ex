defmodule CacheLayer do
  @moduledoc """
  A failure-aware, write-through cache over an arbitrary data source.

  `CacheLayer` is a `GenServer` that owns one `:set`/`:public` ETS table per logical
  *table* name (an atom), created lazily on first use. Values are read through a
  fallback function that may either succeed (`{:ok, value}`) or fail
  (`{:error, reason}`).

    * successful reads are cached permanently (until invalidated);
    * failed reads are *negatively cached* for a bounded number of subsequent serves
      (the `:negative_hits` budget) so that a flapping backend is not hammered, after
      which the entry is evicted and the fallback is retried.

  ## Concurrency

  Cache hits for successes are served straight from ETS with no `GenServer`
  round-trip. Every write, delete and negative-hit decrement is serialised through the
  server process, which guarantees that `fallback_fn` runs **at most once per miss**
  even when many processes race on the same key.

  The table-name → ETS tid registry that powers the lock-free read path lives in
  `:persistent_term` under `{CacheLayer, server_pid, table_name}`. `terminate/2` erases
  every key the server created, so no stale registry entries survive a shutdown.

  ## Example

      {:ok, _pid} = CacheLayer.start_link(name: MyCache, negative_hits: 2)

      CacheLayer.fetch(MyCache, :users, 1, fn -> {:ok, %{id: 1}} end)
      #=> {:ok, %{id: 1}}

      CacheLayer.fetch(MyCache, :users, 2, fn -> {:error, :db_down} end)
      #=> {:error, :db_down}   (cached; the next 2 fetches skip the fallback)

  """

  use GenServer

  @typedoc "A running `CacheLayer` process: a pid or any registered name."
  @type server() :: GenServer.server()

  @typedoc "A logical table name; each maps to its own ETS table."
  @type table() :: atom()

  @typedoc "The zero-arity data-source function used on a cache miss."
  @type fallback() :: (-> {:ok, term()} | {:error, term()})

  @default_negative_hits 3

  ## ------------------------------------------------------------------
  ## Public API
  ## ------------------------------------------------------------------

  @doc """
  Starts the cache server.

  ## Options

    * `:name` - optional name used to register the process (any valid `GenServer` name).
    * `:negative_hits` - a non-negative integer (default `#{@default_negative_hits}`)
      giving how many times a cached failure is served from the cache before it is
      evicted and the fallback retried. `0` disables negative caching entirely.

  All other options are ignored. Returns the usual `GenServer.on_start/0` values.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    negative_hits = Keyword.get(opts, :negative_hits, @default_negative_hits)

    unless is_integer(negative_hits) and negative_hits >= 0 do
      raise ArgumentError,
            ":negative_hits must be a non-negative integer, got: #{inspect(negative_hits)}"
    end

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{negative_hits: negative_hits}, server_opts)
  end

  @doc """
  Fetches `key` from `table`, consulting `fallback_fn` only when needed.

  Behaviour:

    * cached success → `{:ok, value}`, read directly from ETS (no server round-trip);
    * cached failure → `{:error, reason}` without invoking `fallback_fn`; the serve is
      counted against the `:negative_hits` budget and the entry is evicted once the
      budget is exhausted, so the next `fetch/4` retries the backend;
    * miss → `fallback_fn.()` is invoked at most once. `{:ok, value}` is cached
      permanently; `{:error, reason}` is cached negatively unless `:negative_hits` is `0`.

  If `fallback_fn` raises, throws or exits, the failure is re-raised in the calling
  process (the cache server is unaffected and nothing is cached). A return value other
  than `{:ok, value}` / `{:error, reason}` raises an `ArgumentError` in the caller.
  """
  @spec fetch(server(), table(), term(), fallback()) :: {:ok, term()} | {:error, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    case ets_success_lookup(server, table, key) do
      {:ok, _value} = hit ->
        hit

      :other ->
        server
        |> GenServer.call({:fetch, table, key, fallback_fn}, :infinity)
        |> unwrap()
    end
  end

  @doc """
  Removes the cached entry (success *or* negatively cached failure) for `{table, key}`.

  Always returns `:ok`, including when the table or key was never cached.
  """
  @spec invalidate(server(), table(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key}, :infinity)
  end

  @doc """
  Removes every cached entry belonging to `table`, leaving the table itself in place.

  Always returns `:ok`, including when the table was never created.
  """
  @spec invalidate_all(server(), table()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table}, :infinity)
  end

  ## ------------------------------------------------------------------
  ## GenServer callbacks
  ## ------------------------------------------------------------------

  @impl GenServer
  def init(%{negative_hits: negative_hits}) do
    Process.flag(:trap_exit, true)
    {:ok, %{negative_hits: negative_hits, tables: %{}}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    case :ets.lookup(tid, key) do
      [{^key, {:ok, _value} = ok}] ->
        {:reply, ok, state}

      [{^key, {:error, reason}, remaining}] ->
        consume_negative(tid, key, remaining)
        {:reply, {:error, reason}, state}

      [] ->
        {:reply, miss(tid, key, fallback_fn, state.negative_hits), state}
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

  @impl GenServer
  def terminate(_reason, state) do
    for {table, _tid} <- state.tables do
      :persistent_term.erase(registry_key(self(), table))
    end

    :ok
  end

  ## ------------------------------------------------------------------
  ## Internals
  ## ------------------------------------------------------------------

  @spec miss(:ets.tid(), term(), fallback(), non_neg_integer()) :: term()
  defp miss(tid, key, fallback_fn, negative_hits) do
    case invoke(fallback_fn) do
      {:ok, _value} = ok ->
        :ets.insert(tid, {key, ok})
        ok

      {:error, reason} = error ->
        if negative_hits > 0 do
          :ets.insert(tid, {key, {:error, reason}, negative_hits})
        end

        error

      other ->
        other
    end
  end

  @spec invoke(fallback()) :: term()
  defp invoke(fallback_fn) do
    case fallback_fn.() do
      {:ok, _value} = ok -> ok
      {:error, _reason} = error -> error
      other -> {:__cache_layer_invalid__, other}
    end
  catch
    kind, reason ->
      {:__cache_layer_raised__, kind, reason, __STACKTRACE__}
  end

  @spec unwrap(term()) :: {:ok, term()} | {:error, term()}
  defp unwrap({:__cache_layer_raised__, kind, reason, stacktrace}) do
    :erlang.raise(kind, reason, stacktrace)
  end

  defp unwrap({:__cache_layer_invalid__, other}) do
    raise ArgumentError,
          "fallback function must return {:ok, value} or {:error, reason}, got: " <>
            inspect(other)
  end

  defp unwrap(reply), do: reply

  @spec consume_negative(:ets.tid(), term(), pos_integer()) :: :ok
  defp consume_negative(tid, key, remaining) when remaining <= 1 do
    :ets.delete(tid, key)
    :ok
  end

  defp consume_negative(tid, key, remaining) do
    :ets.update_element(tid, key, {3, remaining - 1})
    :ok
  end

  @spec ensure_table(table(), map()) :: {:ets.tid(), map()}
  defp ensure_table(table, state) do
    case Map.fetch(state.tables, table) do
      {:ok, tid} ->
        {tid, state}

      :error ->
        tid = :ets.new(table, [:set, :public, read_concurrency: true])
        :persistent_term.put(registry_key(self(), table), tid)
        {tid, %{state | tables: Map.put(state.tables, table, tid)}}
    end
  end

  @spec ets_success_lookup(server(), table(), term()) :: {:ok, term()} | :other
  defp ets_success_lookup(server, table, key) do
    with pid when is_pid(pid) <- resolve(server),
         tid when tid != :__cache_layer_absent__ <-
           :persistent_term.get(registry_key(pid, table), :__cache_layer_absent__),
         [{^key, {:ok, _value} = ok}] <- :ets.lookup(tid, key) do
      ok
    else
      _other -> :other
    end
  end

  @spec resolve(server()) :: pid() | nil
  defp resolve(server) when is_pid(server), do: server
  defp resolve(server), do: GenServer.whereis(server)

  @spec registry_key(pid(), table()) :: {module(), pid(), table()}
  defp registry_key(pid, table), do: {__MODULE__, pid, table}
end