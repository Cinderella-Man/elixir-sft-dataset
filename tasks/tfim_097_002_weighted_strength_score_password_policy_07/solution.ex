  test "accepts a long, diverse password and reports the capped-range score" do
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn2", %{username: "operator"}) ==
             {:accepted, 92}
  end