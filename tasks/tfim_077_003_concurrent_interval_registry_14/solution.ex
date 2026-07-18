  test "query boundaries are inclusive at both ends", %{server: s} do
    for iv <- [{1, 5}, {5, 6}, {6, 10}, {2, 3}, {10, 12}] do
      {:ok, _} = IntervalRegistry.insert(s, iv)
    end

    assert IntervalRegistry.overlapping(s, {5, 5}) == [{1, 5}, {5, 6}]
    assert IntervalRegistry.overlapping(s, {6, 6}) == [{5, 6}, {6, 10}]
    assert IntervalRegistry.overlapping(s, {3, 5}) == [{1, 5}, {2, 3}, {5, 6}]
    assert IntervalRegistry.overlapping(s, {12, 99}) == [{10, 12}]
    assert IntervalRegistry.overlapping(s, {0, 1}) == [{1, 5}]
    assert IntervalRegistry.stab_count(s, 10) == 2
    assert IntervalRegistry.stab_count(s, 5) == 2
  end