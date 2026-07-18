  test "call/3 raises FunctionClauseError for a bad delay or a non-zero-arity func" do
    # Negative delay: below the non-negative-integer contract.
    assert_raise FunctionClauseError, fn -> Debouncer.call("k", -1, fn -> :noop end) end

    # Non-integer delay.
    assert_raise FunctionClauseError, fn -> Debouncer.call("k", 100.0, fn -> :noop end) end

    # Func of the wrong arity.
    assert_raise FunctionClauseError, fn -> Debouncer.call("k", 100, fn _x -> :noop end) end

    # None of the rejected calls may have been sent to the server: a valid call
    # on the same key still starts a brand-new debounce cycle and fires once.
    Debouncer.call("k", 50, notify(:valid))
    assert_receive :valid, 400
    refute_receive :valid, 200
  end