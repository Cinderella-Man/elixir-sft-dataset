  test "accepts max_ms equal to delay_ms and fires once" do
    # The contract is `max_ms >= delay_ms`, so equality must be accepted.
    assert :ok = MaxWaitDebouncer.call("k", 100, 100, notify(:equal))

    assert_receive :equal, 400
    refute_receive :equal, 200
  end