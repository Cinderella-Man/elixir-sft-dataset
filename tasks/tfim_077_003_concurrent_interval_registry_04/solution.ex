  test "overlapping returns sorted matches", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, _} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _} = IntervalRegistry.insert(s, {10, 15})

    assert [{1, 5}, {3, 8}] = IntervalRegistry.overlapping(s, {4, 6})
    assert [{3, 8}] = IntervalRegistry.overlapping(s, {8, 9})
    assert [] = IntervalRegistry.overlapping(s, {20, 25})
  end