  test "expired lease allows another owner to acquire", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:ok, _} = LeaseManager.acquire(mgr, :printer, :bob)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :printer)
  end