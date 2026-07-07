  test "touching intervals overlap", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, _} = IntervalRegistry.insert(s, {5, 10})
    assert [{1, 5}, {5, 10}] = IntervalRegistry.overlapping(s, {5, 5})
  end