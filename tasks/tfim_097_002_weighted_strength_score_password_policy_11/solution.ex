  test "accepts a password whose score exactly meets the default min_score of 60" do
    # "Xk7#mQpLwT": len 10 -> 20, all 4 classes -> 40, no bonus -> score 60.
    # 60 is not strictly below the default minimum of 60, so it must be accepted.
    assert PasswordPolicy.evaluate("Xk7#mQpLwT", %{username: "operator"}) == {:accepted, 60}
  end