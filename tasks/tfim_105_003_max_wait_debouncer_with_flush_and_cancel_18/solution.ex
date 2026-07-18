  test "after a max-wait fire the next call gets a full fresh window, not the expired one" do
    # Force a max-wait fire at ~t=200 (delay=150, max=200, second call at ~100).
    MaxWaitDebouncer.call("k", 150, 200, notify(:burst_one))
    refute_receive :burst_one, 100
    MaxWaitDebouncer.call("k", 150, 200, notify(:burst_one))
    assert_receive :burst_one, 250

    # Fresh burst: delay=300, max=300 must fire ~300ms from now. If the old
    # first_call_at survived the fire, remaining_until_max would already be
    # ~0-100ms and this would fire almost immediately, inside the refute window.
    MaxWaitDebouncer.call("k", 300, 300, notify(:burst_two))
    refute_receive :burst_two, 200
    assert_receive :burst_two, 350
  end