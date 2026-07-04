  test "value can go negative", %{c: c} do
    Counter.increment(c, :a, 2)
    Counter.decrement(c, :a, 7)
    assert Counter.value(c) == -5
  end