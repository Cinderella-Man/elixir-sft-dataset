  test "the max-wait fire lands near first_call + max_ms, not last_call + delay" do
    # delay=200, max=250. Calls land at roughly t=0, t=80, t=165, each one
    # resetting the delay timer. A debouncer that only honours delay_ms would
    # fire at ~165 + 200 = ~365; the max-wait bound pins the fire at ~250,
    # i.e. within ~85ms of the final call. The window below expires at ~305,
    # so only an implementation that respects max_ms can satisfy it.
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))
    refute_receive :fired, 80
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))
    refute_receive :fired, 80
    MaxWaitDebouncer.call("k", 200, 250, notify(:fired))

    assert_receive :fired, 140
  end