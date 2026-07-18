  test "merging a remote state into an empty set", %{s: s} do
    remote = %{added: MapSet.new([:a, :b, :c]), removed: MapSet.new([:a])}
    assert :ok = TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.members(s) == MapSet.new([:b, :c])
  end