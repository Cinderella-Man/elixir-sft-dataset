  test "remove deletes exactly the stored interval by id", %{server: s} do
    {:ok, id_a} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _id_b} = IntervalRegistry.insert(s, {3, 8})

    assert IntervalRegistry.size(s) == 2
    assert :ok = IntervalRegistry.remove(s, id_a)
    assert IntervalRegistry.size(s) == 1
    # one copy remains
    assert [{3, 8}] = IntervalRegistry.overlapping(s, {1, 10})
  end