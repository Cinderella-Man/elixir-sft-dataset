  test "name option registers the process for public API calls" do
    name = :ttl_cache_named_process

    {:ok, _pid} =
      TTLCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity,
        name: name
      )

    assert :ok = TTLCache.put(name, "k", "v", 1_000)
    assert {:ok, "v"} = TTLCache.get(name, "k")
    assert :ok = TTLCache.delete(name, "k")
    assert :miss = TTLCache.get(name, "k")
  end