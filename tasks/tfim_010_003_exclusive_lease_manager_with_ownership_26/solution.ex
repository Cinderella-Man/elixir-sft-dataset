  test "lease with minimal duration (1ms)", %{mgr: _mgr} do
    {:ok, short} =
      LeaseManager.start_link(
        clock: &Clock.now/0,
        lease_duration_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, _} = LeaseManager.acquire(short, :resource, :alice)
    assert {:ok, :alice, _} = LeaseManager.holder(short, :resource)

    Clock.advance(2)
    assert {:error, :available} = LeaseManager.holder(short, :resource)
  end