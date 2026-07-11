  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingCounter.increment(sc, "key:#{i}")
    end

    # Let all windows expire
    Clock.advance(10_000)

    send(sc, :cleanup)
    :sys.get_state(sc)

    state = :sys.get_state(sc)
    assert map_size(state.keys) == 0
  end