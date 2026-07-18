  test "a fresh server restarts the id sequence at 1", %{server: s} do
    assert {:ok, 1} = IntervalRegistry.insert(s, {3, 4})
    assert {:ok, 2} = IntervalRegistry.insert(s, {3, 4})

    {:ok, other} = IntervalRegistry.start_link()
    assert {:ok, 1} = IntervalRegistry.insert(other, {7, 8})
    assert {:ok, 2} = IntervalRegistry.insert(other, {7, 8})
    assert :ok = IntervalRegistry.stop(other)
  end