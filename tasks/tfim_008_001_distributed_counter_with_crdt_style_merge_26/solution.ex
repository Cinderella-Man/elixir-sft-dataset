  test "large amounts work correctly", %{c: c} do
    Counter.increment(c, :a, 1_000_000)
    Counter.decrement(c, :a, 999_999)
    assert Counter.value(c) == 1
  end