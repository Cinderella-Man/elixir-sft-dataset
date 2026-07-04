  test "expired keys are cleaned up and don't accumulate", %{rl: rl} do
    # Create entries for 100 different keys
    for i <- 1..100 do
      RateLimiter.check(rl, "key:#{i}", 1, 100)
    end

    # Advance past all windows
    Clock.advance(200)

    # Trigger cleanup manually via a message
    # The GenServer should handle a :cleanup message
    send(rl, :cleanup)
    # Give it a moment to process
    :sys.get_state(rl)

    # Now the internal state should not hold 100 keys worth of data
    state = :sys.get_state(rl)
    assert map_size(state.keys) == 0

    # The state is implementation-dependent, but we can check it's a
    # map/struct and that expired keys are gone. We verify by checking
    # that new requests for those keys work fresh (remaining = max - 1)
    assert {:ok, 0} = RateLimiter.check(rl, "key:1", 1, 100)
  end