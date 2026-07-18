  test "force_release removes lease regardless of owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert :ok = LeaseManager.force_release(mgr, :printer)
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end