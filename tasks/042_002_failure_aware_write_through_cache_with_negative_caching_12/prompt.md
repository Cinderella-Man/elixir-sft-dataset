# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `invalidate` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed write-through cache **and handles fallback failures explicitly with negative caching**.

Unlike a naive cache, the data source here can fail (the database is down, the row is being rebuilt, etc.). I want the cache to be *failure-aware*: successes are cached, and failures can be **negatively cached** for a bounded number of subsequent reads so a flapping backend does not get hammered — but the cache must eventually retry.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration, and a `:negative_hits` option (a non-negative integer, default `3`) that controls how many times a cached failure is served before it is evicted and the fallback is retried. It should own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)`. `fallback_fn` is a zero-arity function that returns either `{:ok, value}` or `{:error, reason}`.
  - On a **cache hit for a success**, return `{:ok, value}` (read directly from ETS, no GenServer round-trip).
  - On a **cache hit for a failure**, return `{:error, reason}` *without* calling the fallback, and count the serve toward the `:negative_hits` budget. Once the budget for that entry is exhausted, evict it so the next `fetch` retries the backend.
  - On a **cache miss**, call `fallback_fn.()` **at most once**. If it returns `{:ok, value}`, cache it permanently and return `{:ok, value}`. If it returns `{:error, reason}`, cache it negatively (subject to `:negative_hits`) and return `{:error, reason}`. When `:negative_hits` is `0`, failures are never cached.
- `CacheLayer.invalidate(server, table, key)` which removes the entry (success *or* failure) for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` which removes **all** cached entries for the given `table`. Returns `:ok`.

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. Success reads must be servable directly from ETS without a GenServer call; all writes, deletes, and negative-hit bookkeeping are serialised through the GenServer so `fallback_fn` runs at most once per miss even under concurrent access. The table-name → ETS-tid registry that powers the no-round-trip read path lives in `:persistent_term`, keyed `{CacheLayer, server_pid, table_name}`, and `terminate/2` must erase every entry the server put there so no stale keys survive shutdown.

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.

## The module with `invalidate` missing

```elixir
defmodule CacheLayer do
  @moduledoc """
  A failure-aware, ETS-backed write-through cache implemented as a GenServer.

  Each logical `table` (an atom) maps to a separate `:set`, `:public` ETS table
  owned by this process, created lazily on first use. Successful reads are served
  directly from ETS (no GenServer round-trip); all writes, deletes, and
  negative-hit bookkeeping are serialised through the GenServer so a `fallback_fn`
  runs at most once per cache miss even under concurrent load.

  Entries are stored tagged:

    * `{key, {:ok, value}}`               – a cached success (permanent)
    * `{key, {:neg, reason, remaining}}`  – a cached failure with a remaining
                                            serve budget

  When the failure budget is exhausted the entry is evicted so the next `fetch`
  retries the backend. This bounds how hard a flapping data source is hit while
  still guaranteeing eventual retry.
  """

  use GenServer

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the cache as a GenServer.

  Options:

    * `:name` – optional process registration name.
    * `:negative_hits` – a non-negative integer (default `3`) controlling how
      many times a cached failure is served before it is evicted and the
      fallback is retried. When `0`, failures are never cached.

  The started process owns the lifecycle of every ETS table it creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {neg, gen_opts} = Keyword.pop(opts, :negative_hits, 3)

    unless is_integer(neg) and neg >= 0 do
      raise ArgumentError,
            ":negative_hits must be a non-negative integer, got: #{inspect(neg)}"
    end

    GenServer.start_link(__MODULE__, %{negative_hits: neg}, gen_opts)
  end

  @doc """
  Fetches the value for `{table, key}`, using `fallback_fn` on a cache miss.

  `fallback_fn` is a zero-arity function returning `{:ok, value}` or
  `{:error, reason}`.

    * Cache hit for a success – returns `{:ok, value}` read directly from ETS,
      without a GenServer round-trip.
    * Cache hit for a failure – returns `{:error, reason}` without calling the
      fallback, counting the serve toward the `:negative_hits` budget; once the
      budget is exhausted the entry is evicted so the next fetch retries.
    * Cache miss – calls `fallback_fn` at most once, caching a success
      permanently or a failure negatively (subject to `:negative_hits`).
  """
  @spec fetch(GenServer.server(), atom(), term(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        GenServer.call(server, {:fetch, table, key, fallback_fn})

      tid ->
        case :ets.lookup(tid, key) do
          # Fast path: a cached success can be served without the GenServer.
          [{^key, {:ok, value}}] -> {:ok, value}
          # Misses and negative entries need serialised handling.
          _ -> GenServer.call(server, {:fetch, table, key, fallback_fn})
        end
    end
  end

  def invalidate(server, table, key) when is_atom(table) do
    # TODO
  end

  @doc """
  Removes all cached entries for the given `table`.

  Always returns `:ok`, even if the table has never been used.
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl GenServer
  def init(%{negative_hits: neg}) do
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}, negative_hits: neg}}
  end

  @impl GenServer
  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    {tid, state} = ensure_table(table, state)

    reply =
      case :ets.lookup(tid, key) do
        [{^key, {:ok, value}}] ->
          {:ok, value}

        [{^key, {:neg, reason, remaining}}] ->
          if remaining <= 1 do
            :ets.delete(tid, key)
          else
            :ets.insert(tid, {key, {:neg, reason, remaining - 1}})
          end

          {:error, reason}

        [] ->
          case fallback_fn.() do
            {:ok, value} ->
              :ets.insert(tid, {key, {:ok, value}})
              {:ok, value}

            {:error, reason} ->
              if state.negative_hits > 0 do
                :ets.insert(tid, {key, {:neg, reason, state.negative_hits}})
              end

              {:error, reason}

            other ->
              raise ArgumentError,
                    "fallback_fn must return {:ok, value} or {:error, reason}, " <>
                      "got: #{inspect(other)}"
          end
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

Give me only the complete implementation of `invalidate` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
