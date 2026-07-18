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
    # observe what terminate/2 does on a clean shutdown. terminate/2 must erase
    # the persistent_term entries it created for each table (ETS tables are freed
    # automatically when the owner dies, but persistent_term is NOT — only
    # terminate/2 can clean those up).
    {:ok, pid} = CacheLayer.start_link([])

    assert {:ok, :db_value} = CacheLayer.fetch(pid, :users, "u:1", fn -> :db_value end)
    assert {:ok, :db_value} = CacheLayer.fetch(pid, :posts, "p:1", fn -> :db_value end)

    users_key = {CacheLayer, pid, :users}
    posts_key = {CacheLayer, pid, :posts}

    # While alive, the registry entries exist and point at real ETS tables.
    users_tid = :persistent_term.get(users_key, :no_table)
    posts_tid = :persistent_term.get(posts_key, :no_table)
    assert users_tid != :no_table
    assert posts_tid != :no_table
    assert :ets.info(users_tid) != :undefined
    assert :ets.info(posts_tid) != :undefined

    # Cleanly stop the process; terminate/2 must run and scrub the registry.
    ref = Process.monitor(pid)
    :ok = GenServer.stop(pid, :normal, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

    # If terminate/2 is gutted, these persistent_term entries linger as stale
    # references and these assertions fail.
    assert :persistent_term.get(users_key, :no_table) == :no_table
    assert :persistent_term.get(posts_key, :no_table) == :no_table

    # The ETS tables terminate/2 deleted must also be gone.
    assert :ets.info(users_tid) == :undefined
    assert :ets.info(posts_tid) == :undefined
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
end
