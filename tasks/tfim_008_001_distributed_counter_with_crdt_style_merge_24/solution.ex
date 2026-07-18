  test "merging empty state into populated counter is a no-op", %{c: c} do
    Counter.increment(c, :a, 5)
    before = Counter.state(c)
    Counter.merge(c, %{p: %{}, n: %{}})
    assert Counter.state(c) == before
  end