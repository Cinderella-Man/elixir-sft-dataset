  test "enclosing and stab_count", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 10})
    {:ok, _} = IntervalRegistry.insert(s, {3, 7})
    {:ok, _} = IntervalRegistry.insert(s, {6, 15})
    {:ok, _} = IntervalRegistry.insert(s, {20, 30})

    assert [{1, 10}, {3, 7}, {6, 15}] = IntervalRegistry.enclosing(s, 6)
    assert IntervalRegistry.stab_count(s, 6) == 3
    assert IntervalRegistry.stab_count(s, 25) == 1
    assert IntervalRegistry.stab_count(s, 100) == 0
  end