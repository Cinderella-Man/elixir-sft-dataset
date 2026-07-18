  test "enabled? and enabled_for? read from ETS while the server is unavailable", %{pid: pid} do
    FeatureFlags.enable(:direct_read)
    FeatureFlags.enable_for_percentage(:direct_pct, 100)

    # With the owning process suspended it cannot serve any call; reads must
    # still answer because they go straight to the named ETS table.
    :sys.suspend(pid)

    reader =
      Task.async(fn ->
        {FeatureFlags.enabled?(:direct_read), FeatureFlags.enabled_for?(:direct_pct, "user:1")}
      end)

    outcome = Task.yield(reader, 1_000) || Task.shutdown(reader, :brutal_kill)

    :sys.resume(pid)

    assert outcome == {:ok, {true, true}}
  end