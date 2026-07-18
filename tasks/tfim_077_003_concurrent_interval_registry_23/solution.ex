  test "insert rejects a reversed interval instead of storing it", %{server: s} do
    assert_raise FunctionClauseError, fn -> IntervalRegistry.insert(s, {7, 3}) end
    assert IntervalRegistry.size(s) == 0

    {:ok, _} = IntervalRegistry.insert(s, {3, 7})
    assert IntervalRegistry.size(s) == 1
    assert [{3, 7}] = IntervalRegistry.overlapping(s, {7, 7})
  end