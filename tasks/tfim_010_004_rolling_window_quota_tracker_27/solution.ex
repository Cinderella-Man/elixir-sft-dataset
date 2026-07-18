  test "name option registers the process for lookups" do
    {:ok, _pid} =
      QuotaTracker.start_link(
        name: :quota_tracker_named,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 7} = QuotaTracker.record(:quota_tracker_named, :api, 3, 10, 1_000)
    assert {:ok, 3} = QuotaTracker.usage(:quota_tracker_named, :api, 1_000)
  end