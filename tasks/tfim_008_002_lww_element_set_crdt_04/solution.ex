  test "member? returns false for unknown element", %{s: s} do
    assert LWWSet.member?(s, :missing) == false
  end