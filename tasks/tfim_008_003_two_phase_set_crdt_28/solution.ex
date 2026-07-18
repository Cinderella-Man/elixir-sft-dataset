  test "remote merge that re-adds a locally-removed element cannot resurrect it", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    # Remote never removed :x — it carries :x only in its add-set.
    remote = %{added: MapSet.new([:x]), removed: MapSet.new()}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :x) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end