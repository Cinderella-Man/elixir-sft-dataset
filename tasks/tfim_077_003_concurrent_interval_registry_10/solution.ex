  test "remove updates overlap results", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, mid} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _} = IntervalRegistry.insert(s, {10, 15})

    assert :ok = IntervalRegistry.remove(s, mid)
    assert [{1, 5}] = IntervalRegistry.overlapping(s, {4, 6})
  end