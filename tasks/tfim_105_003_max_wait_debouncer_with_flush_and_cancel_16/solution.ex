  test "a second call restarts the delay window instead of firing at the first call's deadline" do
    # delay=200, max=5000 (max can never bind here). The second call lands at
    # ~t=150, so an implementation that resets the timer fires at ~350. One that
    # kept the original deadline would fire at ~200, inside the refute window.
    MaxWaitDebouncer.call("k", 200, 5000, notify(:reset))
    refute_receive :reset, 150
    MaxWaitDebouncer.call("k", 200, 5000, notify(:reset))
    refute_receive :reset, 150

    assert_receive :reset, 300
  end