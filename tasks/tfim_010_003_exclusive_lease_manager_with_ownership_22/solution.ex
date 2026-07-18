  test "expiring one resource does not affect another", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(500)
    {:ok, _} = LeaseManager.acquire(mgr, :scanner, :bob)

    Clock.advance(501)

    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :scanner)
  end