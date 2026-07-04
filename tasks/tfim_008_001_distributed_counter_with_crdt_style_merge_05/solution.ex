  test "increment with explicit amount", %{c: c} do
    Counter.increment(c, :a, 5)
    assert Counter.value(c) == 5
  end