  test "accepts a zero delay and fires promptly" do
    # delay_ms is a non-negative duration; 0 satisfies `max_ms >= delay_ms`.
    assert :ok = MaxWaitDebouncer.call("k", 0, 500, notify(:zero))

    assert_receive :zero, 400
    refute_receive :zero, 200
  end