  test "decrement with explicit amount", %{c: c} do
    Counter.decrement(c, :a, 3)
    assert Counter.value(c) == -3
  end