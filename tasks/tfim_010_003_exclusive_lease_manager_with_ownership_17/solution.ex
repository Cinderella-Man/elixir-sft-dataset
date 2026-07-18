  test "renew returns error for expired lease", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:error, :not_held} = LeaseManager.renew(mgr, :printer, :alice)
  end