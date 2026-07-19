# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
