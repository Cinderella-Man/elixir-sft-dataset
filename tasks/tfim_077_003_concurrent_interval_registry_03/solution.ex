  test "insert returns unique ids", %{server: s} do
    {:ok, id1} = IntervalRegistry.insert(s, {1, 5})
    {:ok, id2} = IntervalRegistry.insert(s, {1, 5})
    {:ok, id3} = IntervalRegistry.insert(s, {10, 20})

    assert id1 != id2
    assert id2 != id3
    assert IntervalRegistry.size(s) == 3
  end