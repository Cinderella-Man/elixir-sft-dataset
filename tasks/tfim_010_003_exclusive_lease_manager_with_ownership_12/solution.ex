  test "lease is still active just before expiration", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(999)

    assert {:ok, :alice, _} = LeaseManager.holder(mgr, :printer)
  end