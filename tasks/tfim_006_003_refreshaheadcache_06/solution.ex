  test "get below refresh threshold does NOT trigger loader", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # threshold 0.8 of 1000ms = 800ms.  At 500ms we are still "fresh."
    Clock.advance(500)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 0
  end