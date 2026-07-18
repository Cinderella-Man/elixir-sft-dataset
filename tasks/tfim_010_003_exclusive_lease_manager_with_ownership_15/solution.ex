  test "renew extends lease from current time", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(800)
    assert {:ok, new_expires} = LeaseManager.renew(mgr, :printer, :alice)
    assert new_expires == 1_800

    # At 1500ms (700ms since renew) — still active
    Clock.advance(700)
    assert {:ok, :alice, _} = LeaseManager.holder(mgr, :printer)

    # At 1801ms — expired
    Clock.advance(301)
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end