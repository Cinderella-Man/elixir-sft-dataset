  test "mixed increment and decrement on one node", %{c: c} do
    Counter.increment(c, :a, 10)
    Counter.decrement(c, :a, 4)
    assert Counter.value(c) == 6
  end