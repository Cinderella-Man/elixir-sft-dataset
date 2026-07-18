  test "renew returns error for wrong owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :not_held} = LeaseManager.renew(mgr, :printer, :bob)
  end