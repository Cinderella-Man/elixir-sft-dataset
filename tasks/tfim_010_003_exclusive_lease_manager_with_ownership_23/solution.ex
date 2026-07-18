  test "repeated renews keep a lease alive indefinitely", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    for _ <- 1..5 do
      Clock.advance(800)
      assert {:ok, _} = LeaseManager.renew(mgr, :printer, :alice)
    end

    assert {:ok, :alice, _} = LeaseManager.holder(mgr, :printer)
  end