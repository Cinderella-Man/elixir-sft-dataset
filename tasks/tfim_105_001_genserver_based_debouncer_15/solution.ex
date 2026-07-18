  test "a short-delay key fires before a long-delay key that was scheduled earlier" do
    Debouncer.call("long", 250, notify(:long))
    Debouncer.call("short", 50, notify(:short))

    # The short key fires on its own schedule, well before the long one...
    assert_receive :short, 200
    refute_received :long

    # ...and the pending long key is unaffected, firing after its own delay.
    assert_receive :long, 500
  end