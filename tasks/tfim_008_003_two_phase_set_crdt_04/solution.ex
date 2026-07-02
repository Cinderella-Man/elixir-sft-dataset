  test "member? returns false for unknown element", %{s: s} do
    assert TwoPhaseSet.member?(s, :missing) == false
  end