  test "documented example yields the exact state map and value", %{c: c} do
    Counter.increment(c, :a, 3)
    Counter.decrement(c, :a, 1)
    assert Counter.state(c) == %{p: %{a: 3}, n: %{a: 1}}
    assert Counter.value(c) == 2
  end