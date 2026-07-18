  test "check reaches the process through the registered :name" do
    name = :hierarchical_limiter_named_server

    {:ok, _pid} =
      HierarchicalLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    tiers = [{:per_sec, 1, 1_000}]
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(name, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(name, "k", tiers)
  end