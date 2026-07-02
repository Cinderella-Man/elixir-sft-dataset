  test "single decrement", %{c: c} do
    assert :ok = Counter.decrement(c, :a)
    assert Counter.value(c) == -1
  end