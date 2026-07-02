  test "fresh set has no members", %{s: s} do
    assert LWWSet.members(s) == MapSet.new()
  end