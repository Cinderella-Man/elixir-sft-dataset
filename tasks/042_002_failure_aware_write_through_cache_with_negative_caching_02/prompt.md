# Task: Implement `handle_call/3`

Implement the GenServer `handle_call/3` callback for the `CacheLayer` module below.
It is the serialised core of the cache: every write, delete, and negative-hit
bookkeeping operation flows through it. There are three message shapes to handle.

**1. `{:fetch, table, key, fallback_fn}`** — the miss / negative-hit path.

First ensure the ETS table for `table` exists (creating it lazily via
`ensure_table/2`, which returns `{tid, state}`). Then look the `key` up in that
table and compute a reply:

- If the entry is a cached success `{:ok, value}`, reply `{:ok, value}`.
- If the entry is a cached failure `{:neg, reason, remaining}`, count this serve
  against the budget: when `remaining <= 1`, delete the entry (so the next fetch
  retries the backend); otherwise reinsert it with `remaining` decremented by 1.
  Either way reply `{:error, reason}` **without** calling `fallback_fn`.
- If there is no entry, invoke `fallback_fn.()` exactly once:
  - `{:ok, value}` → insert `{key, {:ok, value}}` permanently and reply `{:ok, value}`.
  - `{:error, reason}` → if `state.negative_hits > 0`, insert
    `{key, {:neg, reason, state.negative_hits}}`; then reply `{:error, reason}`
    (when `negative_hits` is `0`, the failure is not cached at all).
  - Anything else → raise `ArgumentError` explaining that `fallback_fn` must
    return `{:ok, value}` or `{:error, reason}`.

Reply with the computed value and the (possibly updated) state.

**2. `{:invalidate, table, key}`** — if the `table` has been created, delete the
entry for `key` from its ETS table; if the table does not exist, do nothing.
Always reply `:ok`.

**3. `{:invalidate_all, table}`** — if the `table` has been created, delete all
objects from its ETS table; if the table does not exist, do nothing. Always
reply `:ok`.

Only the first `:fetch` clause carries the `@impl GenServer` attribute; the other
two clauses follow it directly.

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

  @doc """
  Removes the cached entry (success or failure) for `{table, key}`.

  Always returns `:ok`, even if no entry (or table) exists.
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
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

  def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
    # TODO
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