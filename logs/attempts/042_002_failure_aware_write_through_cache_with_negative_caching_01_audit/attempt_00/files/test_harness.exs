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
    cl = start_cache([])
    Tracker.set({:ok, %{name: "Alice"}})

    assert {:ok, %{name: "Alice"}} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:ok, %{name: "Alice"}} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
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

    slow = fn ->
      Process.sleep(20)
      Tracker.fallback()
    end

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

  test "negative_hits defaults to 3 cached serves before the backend is retried" do
    cl = start_cache([])
    Tracker.set({:error, :db_down})

    # miss -> fallback called once, error cached negatively with the default budget
    assert {:error, :db_down} = CacheLayer.fetch(cl, :defaults, "k", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # exactly three cached serves, none of which touch the backend
    for _ <- 1..3 do
      assert {:error, :db_down} = CacheLayer.fetch(cl, :defaults, "k", &Tracker.fallback/0)
    end

    assert Tracker.count() == 1

    # default budget exhausted -> entry evicted, next fetch retries the backend
    Tracker.set({:ok, :back_up})
    assert {:ok, :back_up} = CacheLayer.fetch(cl, :defaults, "k", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end

  test "the :name option registers the process and the API works through that name" do
    start_supervised!({CacheLayer, name: :cache_layer_named})
    Tracker.set({:ok, :by_name})

    assert {:ok, :by_name} =
             CacheLayer.fetch(:cache_layer_named, :users, "u:1", &Tracker.fallback/0)

    assert {:ok, :by_name} =
             CacheLayer.fetch(:cache_layer_named, :users, "u:1", &Tracker.fallback/0)

    assert Tracker.count() == 1

    assert :ok = CacheLayer.invalidate(:cache_layer_named, :users, "u:1")

    Tracker.set({:ok, :refreshed})

    assert {:ok, :refreshed} =
             CacheLayer.fetch(:cache_layer_named, :users, "u:1", &Tracker.fallback/0)

    assert Tracker.count() == 2
  end

  test "a cached success is served while the GenServer is blocked inside a fallback" do
    cl = start_cache([])
    Tracker.set({:ok, :cached})

    assert {:ok, :cached} = CacheLayer.fetch(cl, :users, "hot", &Tracker.fallback/0)
    assert Tracker.count() == 1

    test_pid = self()

    blocker = fn ->
      send(test_pid, :fallback_entered)

      receive do
        :release -> {:ok, :slow_value}
      end
    end

    # This miss occupies the GenServer until we release it.
    blocked = Task.async(fn -> CacheLayer.fetch(cl, :users, "cold", blocker) end)
    assert_receive :fallback_entered, 1_000

    # The cached success must not need the (busy) GenServer.
    reader = Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", &Tracker.fallback/0) end)
    assert {:ok, :cached} = Task.await(reader, 1_000)
    assert Tracker.count() == 1

    send(cl, :release)
    assert {:ok, :slow_value} = Task.await(blocked, 1_000)
  end

  test "each key carries its own independent negative budget" do
    cl = start_cache(negative_hits: 1)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "a", &Tracker.fallback/0)
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "b", &Tracker.fallback/0)
    assert Tracker.count() == 2

    # one cached serve each: neither key consumes the other's budget
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "a", &Tracker.fallback/0)
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "b", &Tracker.fallback/0)
    assert Tracker.count() == 2

    # each budget is now exhausted independently
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "a", &Tracker.fallback/0)
    assert Tracker.count() == 3
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "b", &Tracker.fallback/0)
    assert Tracker.count() == 4
  end

  test "invalidate_all only clears the named table and leaves other tables cached" do
    cl = start_cache(negative_hits: 5)
    Tracker.set({:ok, :v})

    assert {:ok, :v} = CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    assert {:ok, :v} = CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    :ok = CacheLayer.invalidate_all(cl, :users)

    Tracker.set({:ok, :refetched})

    # :users was cleared -> backend hit again
    assert {:ok, :refetched} = CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 3

    # :posts must be untouched -> still served from cache
    assert {:ok, :v} = CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 3
  end

  test "invalidate returns :ok for an unknown key and an unused table" do
    cl = start_cache([])

    assert :ok = CacheLayer.invalidate(cl, :never_used, "missing")

    Tracker.set({:ok, :v})
    assert {:ok, :v} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # unknown key in a live table: still :ok, and the sibling entry survives
    assert :ok = CacheLayer.invalidate(cl, :users, "u:absent")
    assert {:ok, :v} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end
end
