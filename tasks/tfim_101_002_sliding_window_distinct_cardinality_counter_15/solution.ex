  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingUniqueCounter.add(sc, "key:#{i}", "m#{i}")
    end

    # Let all windows expire
    Clock.advance(10_000)

    send(sc, :cleanup)

    # A subsequent GenServer call is processed after :cleanup, so this
    # observes state through the public API once cleanup has run.
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end