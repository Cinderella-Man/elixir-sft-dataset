  test "both edges with a single call fires leading only (never twice)" do
    EdgeDebouncer.call("k", 150, notify(:solo), edge: :both)

    assert_receive :solo, 100
    # No trailing execution for a lone call.
    refute_receive :solo, 400
  end