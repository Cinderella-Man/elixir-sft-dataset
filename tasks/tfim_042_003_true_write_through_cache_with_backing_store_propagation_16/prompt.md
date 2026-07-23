# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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
          [{^key, value}] -> {:ok, value}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule CacheLayerWriteThroughTest do
  use ExUnit.Case, async: false

  # A mock backing store that records load/write/delete calls and can be
  # toggled to fail its write/delete operations.
  defmodule Store do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{loads: 0, writes: 0, deletes: 0, fail: false} end,
        name: __MODULE__
      )
    end

    def loaded(value) do
      Agent.update(__MODULE__, fn s -> %{s | loads: s.loads + 1} end)
      value
    end

    def write do
      Agent.get_and_update(__MODULE__, fn s ->
        resp = if s.fail, do: {:error, :store_down}, else: :ok
        {resp, %{s | writes: s.writes + 1}}
      end)
    end

    def delete do
      Agent.get_and_update(__MODULE__, fn s ->
        resp = if s.fail, do: {:error, :store_down}, else: :ok
        {resp, %{s | deletes: s.deletes + 1}}
      end)
    end

    def set_fail(bool), do: Agent.update(__MODULE__, fn s -> %{s | fail: bool} end)
    def counts, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Store, :ok})
    cl = start_supervised!({CacheLayer, []})
    %{cl: cl}
  end

  # -------------------------------------------------------
  # Read-through
  # -------------------------------------------------------

  test "fetch loads on a miss and caches for later hits", %{cl: cl} do
    loader = fn -> Store.loaded(:v1) end

    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
    assert Store.counts().loads == 1
  end

  test "concurrent misses call the loader at most once", %{cl: cl} do
    loader = fn ->
      Process.sleep(20)
      Store.loaded(:v)
    end

    results =
      for _ <- 1..25 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", loader) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :v}))
    assert Store.counts().loads == 1
  end

  # -------------------------------------------------------
  # Write-through
  # -------------------------------------------------------

  test "put writes through to the store then updates the cache", %{cl: cl} do
    assert {:ok, :new} = CacheLayer.put(cl, :users, "u:1", :new, &Store.write/0)
    assert Store.counts().writes == 1

    # Subsequent fetch is served from cache — loader never runs.
    assert {:ok, :new} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:from_db) end)
    assert Store.counts().loads == 0
  end

  test "put overwrites an existing cached value", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:old) end)
    assert {:ok, :updated} = CacheLayer.put(cl, :users, "u:1", :updated, &Store.write/0)

    assert {:ok, :updated} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    # Only the original load happened; the second fetch was a cache hit.
    assert Store.counts().loads == 1
  end

  test "a failed write leaves the previously cached value intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.put(cl, :users, "u:1", :v2, &Store.write/0)
    assert Store.counts().writes == 1

    # Cache untouched — still the old value, no reload.
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 1
  end

  # -------------------------------------------------------
  # Delete-through
  # -------------------------------------------------------

  test "delete removes from the store then the cache", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.delete(cl, :users, "u:1", &Store.delete/0)
    assert Store.counts().deletes == 1

    # Cache miss now -> reload.
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end

  test "a failed delete leaves the cached value intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.delete(cl, :users, "u:1", &Store.delete/0)
    assert Store.counts().deletes == 1

    # Still cached — no reload.
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 1
  end

  # -------------------------------------------------------
  # Cache-only invalidation (store untouched)
  # -------------------------------------------------------

  test "invalidate evicts from the cache without touching the store", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.invalidate(cl, :users, "u:1")
    assert Store.counts().deletes == 0

    # Evicted -> reload.
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end

  test "invalidate_all clears the table without touching the store", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", fn -> Store.loaded(i) end)
    end

    assert Store.counts().loads == 5
    assert :ok = CacheLayer.invalidate_all(cl, :users)
    assert Store.counts().deletes == 0

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", fn -> Store.loaded(i) end)
    end

    assert Store.counts().loads == 10
  end

  test "invalidate on a non-existent key returns :ok", %{cl: cl} do
    assert :ok = CacheLayer.invalidate(cl, :users, "nope")
  end

  test "invalidate_all on an unused table returns :ok", %{cl: cl} do
    assert :ok = CacheLayer.invalidate_all(cl, :never_used)
  end

  # -------------------------------------------------------
  # Table independence
  # -------------------------------------------------------

  test "put on one table does not affect another", %{cl: cl} do
    CacheLayer.put(cl, :users, "id:1", :u, &Store.write/0)
    CacheLayer.put(cl, :posts, "id:1", :p, &Store.write/0)

    assert {:ok, :u} = CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:x) end)
    assert {:ok, :p} = CacheLayer.fetch(cl, :posts, "id:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 0
  end

  # -------------------------------------------------------
  # Termination / cleanup (exercises terminate/2)
  # -------------------------------------------------------

  test "stopping the server cleans up its persistent_term registrations" do
    # Snapshot the registry first so the test observes exactly the entries this
    # instance creates, without assuming anything about how they are keyed.
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)

    {:ok, pid} = CacheLayer.start_link([])

    # Touch two tables so both get lazily created and registered.
    assert {:ok, :v1} = CacheLayer.fetch(pid, :cleanup_a, "k", fn -> :v1 end)
    assert {:ok, :v2} = CacheLayer.fetch(pid, :cleanup_b, "k", fn -> :v2 end)

    # While the server is alive both keys are cache hits: a loader that raises
    # proves the values are served from the cache, not reloaded.
    boom = fn -> raise "loader must not run on a cache hit" end
    assert {:ok, :v1} = CacheLayer.fetch(pid, :cleanup_a, "k", boom)
    assert {:ok, :v2} = CacheLayer.fetch(pid, :cleanup_b, "k", boom)

    alive_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    created = MapSet.difference(alive_keys, before_keys)

    # A clean stop must run terminate/2, which erases every registration the
    # server made, whatever naming scheme it chose.
    :ok = GenServer.stop(pid)

    remaining = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created, remaining)
  end

  test "terminate/2 runs during a supervised shutdown without crashing" do
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)

    {:ok, sup} = Supervisor.start_link([{CacheLayer, []}], strategy: :one_for_one)
    [{_id, pid, _type, _mods}] = Supervisor.which_children(sup)

    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", fn -> :v end)
    # A repeat fetch is a cache hit; the raising loader proves it never runs.
    boom = fn -> raise "loader must not run on a cache hit" end
    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", boom)

    alive_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    created = MapSet.difference(alive_keys, before_keys)

    ref = Process.monitor(pid)
    :ok = Supervisor.stop(sup)

    # The child must have exited normally (a raising terminate/2 would surface
    # here as an abnormal exit reason), and its registrations must be gone.
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}
    assert reason in [:normal, :shutdown]

    remaining = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created, remaining)
  end

  test "cache hits are served from ETS while the server is blocked in a loader", %{cl: cl} do
    # TODO
  end

  test "a :name registered server serves fetch, put and invalidate through the name" do
    start_supervised!(Supervisor.child_spec({CacheLayer, [name: :cl_named]}, id: :cl_named))

    assert {:ok, :v1} = CacheLayer.fetch(:cl_named, :users, "u:1", fn -> Store.loaded(:v1) end)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :v1} = CacheLayer.fetch(:cl_named, :users, "u:1", boom)

    assert {:ok, :v2} = CacheLayer.put(:cl_named, :users, "u:1", :v2, &Store.write/0)
    assert {:ok, :v2} = CacheLayer.fetch(:cl_named, :users, "u:1", boom)

    assert :ok = CacheLayer.invalidate(:cl_named, :users, "u:1")
    assert {:ok, :v3} = CacheLayer.fetch(:cl_named, :users, "u:1", fn -> Store.loaded(:v3) end)
    assert Store.counts().loads == 2
  end

  test "put accepts an {:ok, term} writer result and caches the value", %{cl: cl} do
    writer = fn -> {:ok, :store_receipt} end

    assert {:ok, :v2} = CacheLayer.put(cl, :users, "u:1", :v2, writer)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", boom)
    assert Store.counts().loads == 0
  end

  test "delete accepts an {:ok, term} deleter result and evicts the entry", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.delete(cl, :users, "u:1", fn -> {:ok, :deleted_1_row} end)

    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end

  test "a failed put does not populate the cache for a previously uncached key", %{cl: cl} do
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.put(cl, :users, "u:9", :v2, &Store.write/0)

    Store.set_fail(false)

    assert {:ok, :from_store} =
             CacheLayer.fetch(cl, :users, "u:9", fn -> Store.loaded(:from_store) end)

    assert Store.counts().loads == 1
    assert Store.counts().writes == 1
  end

  test "invalidate_all clears only the named table and leaves other tables cached", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:u) end)
    CacheLayer.fetch(cl, :posts, "id:1", fn -> Store.loaded(:p) end)

    assert :ok = CacheLayer.invalidate_all(cl, :users)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :p} = CacheLayer.fetch(cl, :posts, "id:1", boom)
    assert {:ok, :u2} = CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:u2) end)
    assert Store.counts().loads == 3
  end
end
```
