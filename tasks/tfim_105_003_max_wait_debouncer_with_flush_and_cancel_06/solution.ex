  test "flush runs the pending func immediately" do
    MaxWaitDebouncer.call("k", 500, 5000, notify(:flushed))
    assert :ok = MaxWaitDebouncer.flush("k")

    # Runs well before the 500ms delay would have.
    assert_receive :flushed, 200
    # And does not run a second time.
    refute_receive :flushed, 600
  end