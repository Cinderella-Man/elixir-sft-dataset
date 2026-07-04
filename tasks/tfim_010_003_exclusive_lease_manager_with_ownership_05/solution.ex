  test "release frees the resource for the owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert :ok = LeaseManager.release(mgr, :printer, :alice)
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end