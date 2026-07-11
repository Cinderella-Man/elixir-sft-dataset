  test "each call resets the timer" do
    BatchDebouncer.call("k", 200, :first, report(:batch))
    Process.sleep(100)
    BatchDebouncer.call("k", 200, :second, report(:batch))

    # First item's timer (t=200) must not have fired — it was reset at t=100.
    refute_receive {:batch, _}, 150
    assert_receive {:batch, [:first, :second]}, 500
  end