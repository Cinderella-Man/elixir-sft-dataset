  test "release of expired lease returns error", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:error, :not_held} = LeaseManager.release(mgr, :printer, :alice)
  end