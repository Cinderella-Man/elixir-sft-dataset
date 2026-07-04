# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule CacheLayerNegTest do
  use ExUnit.Case, async: false

  # A configurable fallback double: counts invocations and returns a term the
  # test can change between calls.
  defmodule Tracker do
    use Agent

    def start_link(resp), do: Agent.start_link(fn -> {0, resp} end, name: __MODULE__)

    def fallback do
      Agent.get_and_update(__MODULE__, fn {count, resp} -> {resp, {count + 1, resp}} end)
    end

    def count, do: Agent.get(__MODULE__, fn {count, _} -> count end)
    def set(resp), do: Agent.update(__MODULE__, fn {count, _} -> {count, resp} end)
  end

  setup do
    start_supervised!({Tracker, {:ok, :db_value}})
    :ok
  end

  defp start_cache(opts) do
    start_supervised!({CacheLayer, opts})
  end

  # -------------------------------------------------------
  # Success path
  # -------------------------------------------------------

  test "successful fallback is cached permanently" do
    # TODO
  end

  test "nil is a valid cached success value" do
    cl = start_cache([])
    Tracker.set({:ok, nil})

    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", &Tracker.fallback/0)
    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end

  # -------------------------------------------------------
  # Failure path — negative caching disabled
  # -------------------------------------------------------

  test "with negative_hits: 0 every fetch retries the failing backend" do
    cl = start_cache(negative_hits: 0)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  # -------------------------------------------------------
  # Failure path — negative caching enabled
  # -------------------------------------------------------

  test "a cached failure is served for exactly negative_hits reads then retried" do
    cl = start_cache(negative_hits: 2)
    Tracker.set({:error, :db_down})

    # miss -> calls fallback, caches the error
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # two cached serves, no fallback calls
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # budget exhausted -> next fetch retries
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  test "a negatively cached key can recover to a success" do
    cl = start_cache(negative_hits: 1)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # single cached serve, exhausts the budget
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # backend recovers
    Tracker.set({:ok, :recovered})
    assert {:ok, :recovered} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    # success is now cached permanently
    assert {:ok, :recovered} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  # -------------------------------------------------------
  # Invalidation
  # -------------------------------------------------------

  test "invalidate removes a negatively cached entry" do
    cl = start_cache(negative_hits: 5)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    :ok = CacheLayer.invalidate(cl, :users, "u:1")

    Tracker.set({:ok, :fresh})
    assert {:ok, :fresh} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  test "invalidate removes a cached success" do
    cl = start_cache([])
    Tracker.set({:ok, :v})

    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
    :ok = CacheLayer.invalidate(cl, :users, "u:1")
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  test "invalidate_all clears successes and failures for a table" do
    cl = start_cache(negative_hits: 5)

    Tracker.set({:ok, :v})
    CacheLayer.fetch(cl, :users, "ok", &Tracker.fallback/0)
    Tracker.set({:error, :db_down})
    CacheLayer.fetch(cl, :users, "bad", &Tracker.fallback/0)
    assert Tracker.count() == 2

    :ok = CacheLayer.invalidate_all(cl, :users)

    Tracker.set({:ok, :again})
    assert {:ok, :again} = CacheLayer.fetch(cl, :users, "ok", &Tracker.fallback/0)
    assert {:ok, :again} = CacheLayer.fetch(cl, :users, "bad", &Tracker.fallback/0)
    assert Tracker.count() == 4
  end

  test "invalidate_all on an unused table returns :ok" do
    cl = start_cache([])
    assert :ok = CacheLayer.invalidate_all(cl, :never_used)
  end

  # -------------------------------------------------------
  # Table independence
  # -------------------------------------------------------

  test "different tables are independent namespaces" do
    cl = start_cache([])
    Tracker.set({:ok, :v})

    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  # -------------------------------------------------------
  # At-most-once under concurrency
  # -------------------------------------------------------

  test "concurrent misses call the fallback at most once" do
    cl = start_cache([])
    Tracker.set({:ok, :db_value})

    slow = fn -> Process.sleep(20); Tracker.fallback() end

    results =
      for _ <- 1..25 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", slow) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :db_value}))
    assert Tracker.count() == 1
  end

  # -------------------------------------------------------
  # Lifecycle / termination cleanup
  #
  # These tests exercise `terminate/2` directly: on shutdown the process must
  # release the ETS tables it owns and erase the `:persistent_term` registry
  # entries it created for the fast read path. If `terminate/2` is gutted, the
  # persistent_term registration leaks and these assertions fail.
  # -------------------------------------------------------

  test "terminate/2 erases the persistent_term fast-path registry on shutdown" do
    Process.flag(:trap_exit, true)
    {:ok, cl} = CacheLayer.start_link([])
    Tracker.set({:ok, :v})

    assert {:ok, :v} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:ok, :v} = CacheLayer.fetch(cl, :posts, "p:1", &Tracker.fallback/0)

    users_key = {CacheLayer, cl, :users}
    posts_key = {CacheLayer, cl, :posts}

    # The registry entries exist while the process is alive.
    users_tid = :persistent_term.get(users_key)
    posts_tid = :persistent_term.get(posts_key)
    refute :ets.info(users_tid) == :undefined
    refute :ets.info(posts_tid) == :undefined

    # Graceful stop must run terminate/2, which erases every registry entry.
    :ok = GenServer.stop(cl)

    assert :persistent_term.get(users_key, :cleared) == :cleared
    assert :persistent_term.get(posts_key, :cleared) == :cleared
  end

  test "terminate/2 releases ETS tables the process owned" do
    Process.flag(:trap_exit, true)
    {:ok, cl} = CacheLayer.start_link([])
    Tracker.set({:ok, :v})

    assert {:ok, :v} = CacheLayer.fetch(cl, :items, "i:1", &Tracker.fallback/0)

    tid = :persistent_term.get({CacheLayer, cl, :items})
    refute :ets.info(tid) == :undefined

    :ok = GenServer.stop(cl)

    # After terminate/2 (and process death) the owned table is gone.
    assert :ets.info(tid) == :undefined
  end
end
```
