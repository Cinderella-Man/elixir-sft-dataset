  test "leases on different resources are independent", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)
    {:ok, _} = LeaseManager.acquire(mgr, :scanner, :bob)

    LeaseManager.release(mgr, :printer, :alice)

    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :scanner)
  end