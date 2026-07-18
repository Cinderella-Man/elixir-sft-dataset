  test "acquire uses default 30000ms lease duration when unspecified", %{mgr: _mgr} do
    {:ok, dflt} =
      LeaseManager.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, _} = LeaseManager.acquire(dflt, :printer, :alice)
    assert {:ok, :alice, 30_000} = LeaseManager.holder(dflt, :printer)

    Clock.advance(30_000)
    assert {:error, :available} = LeaseManager.holder(dflt, :printer)
  end