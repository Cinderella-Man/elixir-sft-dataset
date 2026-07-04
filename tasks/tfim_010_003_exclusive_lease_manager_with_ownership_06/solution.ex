  test "release returns error for wrong owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :not_held} = LeaseManager.release(mgr, :printer, :bob)
  end