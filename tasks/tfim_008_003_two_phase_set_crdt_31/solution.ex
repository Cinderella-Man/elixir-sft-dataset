  test "adding a present element again returns :ok and does not change state", %{s: s} do
    TwoPhaseSet.add(s, :x)
    before = TwoPhaseSet.state(s)

    assert :ok = TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.state(s) == before
  end