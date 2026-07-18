  test "merge is idempotent", %{c: c} do
    Counter.increment(c, :a, 3)
    remote = %{p: %{a: 5, b: 2}, n: %{a: 1}}

    Counter.merge(c, remote)
    value_after_first = Counter.value(c)
    state_after_first = Counter.state(c)

    Counter.merge(c, remote)
    value_after_second = Counter.value(c)
    state_after_second = Counter.state(c)

    assert value_after_first == value_after_second
    assert state_after_first == state_after_second
  end