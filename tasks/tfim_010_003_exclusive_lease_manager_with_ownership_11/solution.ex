  test "lease expires after duration", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end