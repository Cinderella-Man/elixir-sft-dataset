  test "ids start at 1 and advance by exactly one per insert", %{server: s} do
    assert {:ok, 1} = IntervalRegistry.insert(s, {1, 2})
    assert {:ok, 2} = IntervalRegistry.insert(s, {1, 2})
    assert {:ok, 3} = IntervalRegistry.insert(s, {5, 9})

    # Removing an id does not rewind or reuse the counter.
    assert :ok = IntervalRegistry.remove(s, 2)
    assert {:ok, 4} = IntervalRegistry.insert(s, {0, 0})

    assert :ok = IntervalRegistry.remove(s, 1)
    assert :ok = IntervalRegistry.remove(s, 3)
    assert :ok = IntervalRegistry.remove(s, 4)
    assert IntervalRegistry.size(s) == 0

    assert {:ok, 5} = IntervalRegistry.insert(s, {2, 2})
    assert [{2, 2}] = IntervalRegistry.enclosing(s, 2)
  end