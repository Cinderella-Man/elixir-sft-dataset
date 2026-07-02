  test "member? returns false for unknown element", %{s: s} do
    assert ORSet.member?(s, :missing) == false
  end