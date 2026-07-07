  test "empty registry queries", %{server: s} do
    assert [] = IntervalRegistry.overlapping(s, {1, 10})
    assert [] = IntervalRegistry.enclosing(s, 5)
    assert IntervalRegistry.stab_count(s, 5) == 0
    assert IntervalRegistry.size(s) == 0
  end