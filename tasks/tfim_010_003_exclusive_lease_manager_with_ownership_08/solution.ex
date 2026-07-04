  test "resource can be re-acquired after release", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)
    :ok = LeaseManager.release(mgr, :printer, :alice)

    assert {:ok, _} = LeaseManager.acquire(mgr, :printer, :bob)
  end