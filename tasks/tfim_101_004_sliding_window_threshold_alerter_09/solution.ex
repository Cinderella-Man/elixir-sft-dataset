  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingAlerter.record(sc, "key:#{i}")
    end

    Clock.advance(10_000)
    send(sc, :cleanup)

    # A subsequent synchronous call is processed after the :cleanup message,
    # so every expired key is observably empty through the public API.
    for i <- 1..50 do
      assert 0 = SlidingAlerter.count(sc, "key:#{i}")
      assert :ok = SlidingAlerter.status(sc, "key:#{i}")
    end
  end