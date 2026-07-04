  test "multiple nodes contribute to the value", %{c: c} do
    Counter.increment(c, :a, 3)
    Counter.increment(c, :b, 5)
    Counter.decrement(c, :a, 1)
    Counter.decrement(c, :b, 2)
    # value = (3 + 5) - (1 + 2) = 5
    assert Counter.value(c) == 5
  end