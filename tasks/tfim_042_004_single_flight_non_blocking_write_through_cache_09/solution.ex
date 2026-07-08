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