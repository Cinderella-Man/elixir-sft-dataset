  test "merging a remote state into an empty counter", %{c: c} do
    remote = %{p: %{a: 5, b: 3}, n: %{a: 1}}
    assert :ok = Counter.merge(c, remote)

    assert Counter.value(c) == 5 + 3 - 1
    state = Counter.state(c)
    assert state.p[:a] == 5
    assert state.p[:b] == 3
    assert state.n[:a] == 1
  end