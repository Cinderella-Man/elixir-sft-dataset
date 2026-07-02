  test "does not execute before the delay elapses" do
    Debouncer.call("k", 200, notify(:done))

    # Well before the 200ms delay, nothing should have fired.
    refute_receive :done, 120

    # But it does fire once the delay has passed.
    assert_receive :done, 400
  end