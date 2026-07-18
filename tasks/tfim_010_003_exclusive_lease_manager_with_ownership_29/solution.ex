  test "server is reachable through the registered :name option", %{mgr: _mgr} do
    name = :lease_manager_named_test

    {:ok, _} =
      LeaseManager.start_link(
        name: name,
        clock: &Clock.now/0,
        lease_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, _} = LeaseManager.acquire(name, :printer, :alice)
    assert {:ok, :alice, _} = LeaseManager.holder(name, :printer)
  end