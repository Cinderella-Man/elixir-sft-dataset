  test "enclosing sorts results and includes both endpoints of each interval", %{server: s} do
    for iv <- [{9, 12}, {1, 5}, {5, 5}, {-3, 1}, {2, 9}] do
      {:ok, _} = IntervalRegistry.insert(s, iv)
    end

    assert IntervalRegistry.enclosing(s, 1) == [{-3, 1}, {1, 5}]
    assert IntervalRegistry.enclosing(s, 5) == [{1, 5}, {2, 9}, {5, 5}]
    assert IntervalRegistry.enclosing(s, 9) == [{2, 9}, {9, 12}]
    assert IntervalRegistry.enclosing(s, 12) == [{9, 12}]
    assert IntervalRegistry.enclosing(s, 13) == []
  end