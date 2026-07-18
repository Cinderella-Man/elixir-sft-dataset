  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingSum.add(sc, "key:#{i}", i)
    end

    # Advance past the cleanup's maximum retention window (24 hours) so every
    # bucket is guaranteed to have expired.
    Clock.advance(24 * 60 * 60 * 1_000 + 1_000)
    send(sc, :cleanup)

    # The follow-up call is processed after the :cleanup message, so it acts as
    # a synchronization barrier and observes the post-cleanup key set.
    assert SlidingSum.keys(sc) == []
  end