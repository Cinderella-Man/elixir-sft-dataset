  test "holder returns owner and expiry for held resource", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:ok, :alice, expires_at} = LeaseManager.holder(mgr, :printer)
    assert expires_at == 1_000
  end