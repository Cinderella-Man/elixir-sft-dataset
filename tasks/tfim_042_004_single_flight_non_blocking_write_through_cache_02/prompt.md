# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CacheLayer do
  @moduledoc """
  An ETS-backed read cache with a single-flight, non-blocking concurrency model.

  Each logical `table` (an atom) maps to a separate `:set`, `:public` ETS table
  owned by this process, created lazily on first use. Cache hits are served
  directly from ETS with no GenServer round-trip.

  ## Single-flight

  The expensive `fallback_fn` runs in the *caller's* process, never inside the
  GenServer, so a slow load for one key does not block loads for other keys.
  For a given `{table, key}`:

    * The first caller to miss becomes the **leader** and runs `fallback_fn`.
    * Concurrent callers become **followers**: their `fetch` call is parked
      inside the GenServer (no reply) until the leader finishes, at which point
      they receive the leader's value. `fallback_fn` is therefore invoked at
      most once per cache miss.

  If the leader crashes before reporting a value (monitored via
  `Process.monitor/1`), all parked followers are told to `:retry`, so they never
  hang — one of them becomes the new leader.
  """

  use GenServer

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the cache as a GenServer.

  Accepts the usual GenServer options, notably `:name` for process registration.
  The started process owns the lifecycle of every ETS table it creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Fetches the value cached under `{table, key}`, computing it on a miss.

  On a cache hit the value is read directly from ETS with no GenServer
  round-trip. On a miss the caller joins the single-flight protocol: exactly one
  racing caller runs `fallback_fn`, the rest wait for and receive its result.
  Always returns `{:ok, value}`.
  """
  @spec fetch(GenServer.server(), atom(), term(), (-> term())) :: {:ok, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        join_and_compute(server, table, key, fallback_fn)

      tid ->
        case :ets.lookup(tid, key) do
          [{^key, value}] -> {:ok, value}
          [] -> join_and_compute(server, table, key, fallback_fn)
        end
    end
  end

  @doc """
  Removes the cached entry for `{table, key}`. Always returns `:ok`.
  """
  @spec invalidate(GenServer.server(), atom(), term()) :: :ok
  def invalidate(server, table, key) when is_atom(table) do
    GenServer.call(server, {:invalidate, table, key})
  end

  @doc """
  Removes every cached entry for `table`. Always returns `:ok`.
  """
  @spec invalidate_all(GenServer.server(), atom()) :: :ok
  def invalidate_all(server, table) when is_atom(table) do
    GenServer.call(server, {:invalidate_all, table})
  end

  # Single-flight participation. Runs the fallback in THIS process when elected
  # leader; blocks (via a parked GenServer call) when a follower.
  defp join_and_compute(server, table, key, fallback_fn) do
    case GenServer.call(server, {:join, table, key}, :infinity) do
      {:hit, value} ->
        {:ok, value}

      {:value, value} ->
        # A follower whose leader completed.
        {:ok, value}

      :retry ->
        # Leader failed; try again (we may become the new leader).
        join_and_compute(server, table, key, fallback_fn)

      {:leader, _ref} ->
        try do
          value = fallback_fn.()
          :ok = GenServer.call(server, {:done, table, key, value}, :infinity)
          {:ok, value}
        rescue
          e ->
            GenServer.call(server, {:fail, table, key}, :infinity)
            reraise e, __STACKTRACE__
        end
    end
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}, inflight: %{}}}
  end

  @impl GenServer
  def handle_call({:join, table, key}, from, state) do
    {tid, state} = ensure_table(table, state)

    case :ets.lookup(tid, key) do
      [{^key, value}] ->
        {:reply, {:hit, value}, state}

      [] ->
        flight_key = {table, key}

        case Map.get(state.inflight, flight_key) do
          nil ->
            leader = elem(from, 0)
            mref = Process.monitor(leader)
            entry = %{leader: leader, mref: mref, waiters: []}
            inflight = Map.put(state.inflight, flight_key, entry)
            {:reply, {:leader, mref}, %{state | inflight: inflight}}

          entry ->
            entry = %{entry | waiters: [from | entry.waiters]}
            {:noreply, %{state | inflight: Map.put(state.inflight, flight_key, entry)}}
        end
    end
  end

  def handle_call({:done, table, key, value}, _from, state) do
    {tid, state} = ensure_table(table, state)
    :ets.insert(tid, {key, value})

    flight_key = {table, key}

    case Map.pop(state.inflight, flight_key) do
      {nil, _} ->
        {:reply, :ok, state}

      {entry, inflight} ->
        Process.demonitor(entry.mref, [:flush])
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, {:value, value}) end)
        {:reply, :ok, %{state | inflight: inflight}}
    end
  end

  def handle_call({:fail, table, key}, _from, state) do
    flight_key = {table, key}

    case Map.pop(state.inflight, flight_key) do
      {nil, _} ->
        {:reply, :ok, state}

      {entry, inflight} ->
        Process.demonitor(entry.mref, [:flush])
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, :retry) end)
        {:reply, :ok, %{state | inflight: inflight}}
    end
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
  def handle_info({:DOWN, mref, :process, _pid, _reason}, state) do
    case Enum.find(state.inflight, fn {_k, entry} -> entry.mref == mref end) do
      nil ->
        {:noreply, state}

      {flight_key, entry} ->
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, :retry) end)
        {:noreply, %{state | inflight: Map.delete(state.inflight, flight_key)}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

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
defmodule CacheLayerSingleFlightTest do
  use ExUnit.Case, async: false

  defmodule Tracker do
    use Agent

    def start_link(value), do: Agent.start_link(fn -> {0, value} end, name: __MODULE__)

    def fallback do
      Agent.get_and_update(__MODULE__, fn {count, value} -> {value, {count + 1, value}} end)
    end

    def count, do: Agent.get(__MODULE__, fn {count, _} -> count end)
  end

  setup do
    start_supervised!({Tracker, :db_value})
    cl = start_supervised!({CacheLayer, []})
    %{cl: cl}
  end

  # -------------------------------------------------------
  # Basic behaviour
  # -------------------------------------------------------

  test "cache miss calls the fallback and returns the value", %{cl: cl} do
    # TODO
  end

  test "cache hit does not call the fallback again", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end

  test "nil is a valid cached value and is not recomputed", %{cl: cl} do
    fun = fn -> nil end
    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", fun)
    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", fun)
  end

  # -------------------------------------------------------
  # Single-flight coalescing
  # -------------------------------------------------------

  test "concurrent misses of the same key run the fallback exactly once", %{cl: cl} do
    fun = fn ->
      Process.sleep(40)
      Tracker.fallback()
    end

    results =
      for _ <- 1..30 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", fun) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :db_value}))
    assert Tracker.count() == 1
  end

  # -------------------------------------------------------
  # Non-blocking: distinct keys compute concurrently
  # -------------------------------------------------------

  test "a slow load for one key does not block loads for another key", %{cl: cl} do
    parent = self()

    # Leader for :a announces itself and blocks until told to proceed.
    slow_a = fn ->
      send(parent, {:a_leading, self()})

      receive do
        :go -> :val_a
      end
    end

    task_a = Task.async(fn -> CacheLayer.fetch(cl, :t, :a, slow_a) end)

    a_pid =
      receive do
        {:a_leading, pid} -> pid
      after
        1_000 -> flunk("leader for :a never started")
      end

    # While :a's fallback is blocked (running OUTSIDE the GenServer), a fetch
    # for a different key must complete promptly.
    assert {:ok, :val_b} = CacheLayer.fetch(cl, :t, :b, fn -> :val_b end)

    # Release :a and confirm it resolves.
    send(a_pid, :go)
    assert {:ok, :val_a} = Task.await(task_a)
  end

  # -------------------------------------------------------
  # Leader failure: followers do not hang, they retry
  # -------------------------------------------------------

  test "if the leader crashes, a waiting follower retries and succeeds", %{cl: cl} do
    parent = self()

    # The leader signals, then crashes without producing a value.
    crashing = fn ->
      send(parent, :leader_ready)
      Process.sleep(30)
      raise "boom"
    end

    leader =
      Task.async(fn ->
        try do
          CacheLayer.fetch(cl, :t, :k, crashing)
        rescue
          _ -> :crashed
        end
      end)

    receive do
      :leader_ready -> :ok
    after
      1_000 -> flunk("leader never started")
    end

    # A follower joins while the leader is still "computing".
    follower =
      Task.async(fn -> CacheLayer.fetch(cl, :t, :k, fn -> :recovered end) end)

    assert :crashed = Task.await(leader)
    assert {:ok, :recovered} = Task.await(follower, 2_000)
  end

  # -------------------------------------------------------
  # Leader hard-killed: DOWN monitor (handle_info/2) rescues followers
  # -------------------------------------------------------

  test "if the leader process is hard-killed, followers retry via the DOWN monitor",
       %{cl: cl} do
    parent = self()

    # The leader announces its pid then blocks forever; a hard kill means no
    # rescue clause can run, so ONLY the GenServer's Process.monitor/DOWN
    # handling (in handle_info/2) can unblock a parked follower.
    blocking = fn ->
      send(parent, {:leader_pid, self()})
      Process.sleep(:infinity)
    end

    # Unlinked spawn so killing the leader does not take down the test process.
    leader_pid = spawn(fn -> CacheLayer.fetch(cl, :t, :down_key, blocking) end)

    receive do
      {:leader_pid, ^leader_pid} -> :ok
    after
      1_000 -> flunk("leader never started")
    end

    # A follower parks inside the GenServer, waiting on the leader's result.
    follower =
      Task.async(fn -> CacheLayer.fetch(cl, :t, :down_key, fn -> :recovered end) end)

    # Give the follower time to register as a waiter before the leader dies.
    Process.sleep(80)

    # Hard kill: untrappable, so the leader cannot report {:fail, ...}. The only
    # thing that can rescue the follower is the monitored :DOWN message routed
    # through handle_info/2. If that clause is gutted, the follower hangs and
    # this assertion times out.
    Process.exit(leader_pid, :kill)

    assert {:ok, :recovered} = Task.await(follower, 2_000)

    # The recovered value must now be cached without recomputation.
    assert {:ok, :recovered} = CacheLayer.fetch(cl, :t, :down_key, fn -> :other end)
  end

  # -------------------------------------------------------
  # Termination: terminate/2 cleans up its table registry
  # -------------------------------------------------------

  test "terminating the cache erases the persistent_term registry for its tables" do
    # Start an unsupervised instance we fully control the lifecycle of, so we can
    # observe what terminate/2 does on a clean shutdown. ETS tables are freed
    # automatically when their owner dies, but persistent_term entries are NOT --
    # only terminate/2 can clean those up. Snapshot the registry and the live
    # table list first so the test observes exactly what this instance creates,
    # without assuming anything about how the entries are named.
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    before_tabs = MapSet.new(:ets.all())

    {:ok, pid} = CacheLayer.start_link([])

    assert {:ok, :db_value} = CacheLayer.fetch(pid, :users, "u:1", fn -> :db_value end)
    assert {:ok, :db_value} = CacheLayer.fetch(pid, :posts, "p:1", fn -> :db_value end)

    # While alive, both entries are cache hits: a fallback that raises proves
    # the values are served from the cache.
    boom = fn -> raise "fallback must not run on a cache hit" end
    assert {:ok, :db_value} = CacheLayer.fetch(pid, :users, "u:1", boom)
    assert {:ok, :db_value} = CacheLayer.fetch(pid, :posts, "p:1", boom)

    created_keys =
      MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
      |> MapSet.difference(before_keys)

    created_tabs = MapSet.difference(MapSet.new(:ets.all()), before_tabs)

    # Cleanly stop the process; terminate/2 must run and scrub the registry.
    ref = Process.monitor(pid)
    :ok = GenServer.stop(pid, :normal, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

    # If terminate/2 is gutted, whatever persistent_term entries the instance
    # created linger as stale references and this assertion fails.
    remaining_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created_keys, remaining_keys)

    # Every ETS table created for this instance must be gone as well.
    assert MapSet.disjoint?(created_tabs, MapSet.new(:ets.all()))
  end

  test "shutdown by a supervisor erases the persistent_term registry for its tables" do
    # A supervisor stops a child by sending it an exit signal rather than calling
    # GenServer.stop/3, and terminate/2 only runs for a server that traps exits.
    # This is the ordinary shutdown path, so a cache stopped this way must also
    # leave no process-global registration behind. Snapshot the registry and the
    # live table list first, assuming nothing about how entries are named.
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    before_tabs = MapSet.new(:ets.all())

    {:ok, sup} = Supervisor.start_link([{CacheLayer, []}], strategy: :one_for_one)
    [{_id, pid, _type, _modules}] = Supervisor.which_children(sup)

    table = :"sup_shutdown_#{System.pid()}_#{System.unique_integer([:positive])}"
    assert {:ok, :db_value} = CacheLayer.fetch(pid, table, "u:1", fn -> :db_value end)

    boom = fn -> raise "fallback must not run on a cache hit" end
    assert {:ok, :db_value} = CacheLayer.fetch(pid, table, "u:1", boom)

    created_keys =
      MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
      |> MapSet.difference(before_keys)

    created_tabs = MapSet.difference(MapSet.new(:ets.all()), before_tabs)

    # Supervisor.stop/2 terminates the child with an exit signal and waits for it.
    ref = Process.monitor(pid)
    :ok = Supervisor.stop(sup, :normal)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000

    # A server that never trapped exits dies before terminate/2 can run, leaving
    # its process-global entries behind, and this assertion fails.
    remaining_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created_keys, remaining_keys)

    # The ETS tables die with their owner in either case.
    assert MapSet.disjoint?(created_tabs, MapSet.new(:ets.all()))
  end

  # -------------------------------------------------------
  # Invalidation
  # -------------------------------------------------------

  test "invalidate forces the next fetch to recompute", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    :ok = CacheLayer.invalidate(cl, :users, "u:1")

    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  test "invalidate only removes the targeted key", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :users, "u:2", &Tracker.fallback/0)
    assert Tracker.count() == 2

    CacheLayer.invalidate(cl, :users, "u:1")

    CacheLayer.fetch(cl, :users, "u:2", &Tracker.fallback/0)
    assert Tracker.count() == 2

    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 3
  end

  test "invalidate_all clears every key in the table", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &Tracker.fallback/0)
    end

    assert Tracker.count() == 5
    :ok = CacheLayer.invalidate_all(cl, :users)

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &Tracker.fallback/0)
    end

    assert Tracker.count() == 10
  end

  test "invalidate_all on an unused table returns :ok", %{cl: cl} do
    assert :ok = CacheLayer.invalidate_all(cl, :never_used)
  end

  # -------------------------------------------------------
  # Table independence
  # -------------------------------------------------------

  test "different tables are independent namespaces", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  test "a cache registered under :name serves fetches and hits through that name" do
    pid = start_supervised!({CacheLayer, [name: :named_cache_layer]}, id: :named_cache)
    assert Process.whereis(:named_cache_layer) == pid

    assert {:ok, :db_value} =
             CacheLayer.fetch(:named_cache_layer, :users, "u:1", &Tracker.fallback/0)

    assert Tracker.count() == 1

    # A hit must be locatable via the registered name alone, with no recompute.
    boom = fn -> raise "fallback must not run on a cache hit" end
    assert {:ok, :db_value} = CacheLayer.fetch(:named_cache_layer, :users, "u:1", boom)
    assert Tracker.count() == 1

    assert :ok = CacheLayer.invalidate(:named_cache_layer, :users, "u:1")

    assert {:ok, :db_value} =
             CacheLayer.fetch(:named_cache_layer, :users, "u:1", &Tracker.fallback/0)

    assert Tracker.count() == 2
  end

  test "a cache hit is served while the cache process is suspended and answers no calls",
       %{cl: cl} do
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # Suspended: the process still runs, but any GenServer call queues forever.
    # A hit that round-trips through the server would therefore never return.
    :sys.suspend(cl)

    task =
      Task.async(fn ->
        CacheLayer.fetch(cl, :users, "u:1", fn -> :must_not_run end)
      end)

    try do
      assert {:ok, :db_value} = Task.await(task, 500)
    after
      :sys.resume(cl)
    end

    assert Tracker.count() == 1
  end

  test "followers are handed the leader's value and never run their own fallback", %{cl: cl} do
    parent = self()

    leader_fun = fn ->
      send(parent, {:leading, self()})

      receive do
        :go -> :leader_value
      end
    end

    leader = Task.async(fn -> CacheLayer.fetch(cl, :t, :shared, leader_fun) end)
    assert_receive {:leading, leader_pid}, 1_000

    # Every follower passes a fallback that must never be invoked: whether it
    # parks behind the leader or arrives after the insert, the value it gets
    # must be the LEADER's value.
    followers =
      for _ <- 1..5 do
        Task.async(fn ->
          CacheLayer.fetch(cl, :t, :shared, fn -> raise "follower fallback must not run" end)
        end)
      end

    send(leader_pid, :go)

    assert {:ok, :leader_value} = Task.await(leader, 2_000)

    for f <- followers do
      assert {:ok, :leader_value} = Task.await(f, 2_000)
    end
  end

  test "a table's ETS table appears only on first use and is readable from other processes",
       %{cl: cl} do
    before_tabs = MapSet.new(:ets.all())

    # Touching a table that was never fetched must not create anything.
    assert :ok = CacheLayer.invalidate_all(cl, :lazy)
    assert :ok = CacheLayer.invalidate(cl, :lazy, "k")
    assert MapSet.difference(MapSet.new(:ets.all()), before_tabs) |> MapSet.size() == 0

    assert {:ok, :v} = CacheLayer.fetch(cl, :lazy, "k", fn -> :v end)

    created = MapSet.difference(MapSet.new(:ets.all()), before_tabs)
    assert MapSet.size(created) == 1

    # A :public table can be read straight from an unrelated process; a
    # :protected one would blow up in :ets.lookup outside the owner.
    boom = fn -> raise "fallback must not run on a cache hit" end
    task = Task.async(fn -> CacheLayer.fetch(cl, :lazy, "k", boom) end)
    assert {:ok, :v} = Task.await(task, 1_000)
  end

  test "invalidate_all leaves entries cached in other tables intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    assert :ok = CacheLayer.invalidate_all(cl, :users)

    boom = fn -> raise ":posts must survive invalidate_all(:users)" end
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :posts, "id:1", boom)
    assert Tracker.count() == 2

    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 3
  end
end
```
