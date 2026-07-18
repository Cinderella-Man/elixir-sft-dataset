  test "a call after flush starts a fresh burst with an untouched max-wait window" do
    # Both durations respect the `max_ms >= delay_ms` contract; the flush below
    # runs the pending func long before either bound would fire it.
    MaxWaitDebouncer.call("k", 500, 500, notify(:pending))
    assert :ok = MaxWaitDebouncer.flush("k")
    assert_receive :pending, 200

    # If flush left the burst start behind, the ~300ms max window would already
    # be spent and this call would fire near-immediately instead of at ~+250.
    MaxWaitDebouncer.call("k", 250, 300, notify(:refreshed))
    refute_receive :refreshed, 150
    assert_receive :refreshed, 300
  end