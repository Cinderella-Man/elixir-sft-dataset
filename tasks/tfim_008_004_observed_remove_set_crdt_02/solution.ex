  test "fresh set has no members", %{s: s} do
    assert ORSet.members(s) == MapSet.new()
  end