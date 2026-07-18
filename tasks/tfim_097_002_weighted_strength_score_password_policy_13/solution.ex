  test "length points count at most 20 characters" do
    # 21 lowercase letters: length points capped at min(21, 20) * 2 = 40, lowercase class
    # only -> 10, len >= 16 -> +20. Score 70 exactly (not 68, not 72).
    assert PasswordPolicy.evaluate("abcdefghijklmnopqrstu", %{username: "operator"}) ==
             {:accepted, 70}
  end