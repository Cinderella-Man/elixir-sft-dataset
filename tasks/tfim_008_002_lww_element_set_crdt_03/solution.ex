  test "single add makes element a member", %{s: s} do
    assert :ok = LWWSet.add(s, :x, 1)
    assert LWWSet.member?(s, :x) == true
    assert LWWSet.members(s) == MapSet.new([:x])
  end