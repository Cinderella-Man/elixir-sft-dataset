  test "merge introduces tombstones from remote that override local adds", %{s: s} do
    TwoPhaseSet.add(s, :a)
    assert TwoPhaseSet.member?(s, :a) == true

    # Remote has removed :a
    remote = %{added: MapSet.new([:a]), removed: MapSet.new([:a])}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :a) == false
  end