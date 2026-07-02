  test "single increment", %{c: c} do
    assert :ok = Counter.increment(c, :a)
    assert Counter.value(c) == 1
  end