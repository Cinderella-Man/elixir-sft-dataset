  test "accepts a moderately strong password at the default threshold" do
    # "Tr0ub4dor&3": len 11 -> 22, all 4 classes -> 40, no bonus -> score 62 (>= 60).
    assert PasswordPolicy.evaluate("Tr0ub4dor&3", %{username: "alice"}) == {:accepted, 62}
  end