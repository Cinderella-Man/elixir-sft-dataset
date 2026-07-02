  test "fires by max_ms even though the delay timer keeps resetting" do
    # delay=150, max=250. A plain debouncer would keep pushing the fire to
    # ~last_call + 150; the max-wait bound forces a fire at ~first_call + 250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=100: resets delay timer (would fire at ~250 anyway)
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=200: delay would push fire to ~350, but max deadline is ~250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))

    # From here (~t=200) the max deadline (~250) is only ~50ms away, well before
    # the ~350 the delay timer would give.
    assert_receive :fired, 175
  end