  test "default amount is 1 for both increment and decrement", %{c: c} do
    Counter.increment(c, :a)
    Counter.increment(c, :a)
    Counter.decrement(c, :a)
    assert Counter.value(c) == 1
  end