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