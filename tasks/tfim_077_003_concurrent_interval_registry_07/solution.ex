  test "degenerate interval", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {4, 4})
    assert [{4, 4}] = IntervalRegistry.enclosing(s, 4)
    assert [] = IntervalRegistry.enclosing(s, 5)
    assert IntervalRegistry.stab_count(s, 4) == 1
  end