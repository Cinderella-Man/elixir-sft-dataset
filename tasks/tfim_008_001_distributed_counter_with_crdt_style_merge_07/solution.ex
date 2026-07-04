  test "increments accumulate for the same node", %{c: c} do
    Counter.increment(c, :a, 2)
    Counter.increment(c, :a, 3)
    assert Counter.value(c) == 5
  end