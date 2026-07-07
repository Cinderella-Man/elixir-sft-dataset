  test "rejects a short weak password with all applicable reasons" do
    # "abc": len 3 -> 6, lowercase only -> 10, score 16. too_short and insufficient_strength.
    assert PasswordPolicy.evaluate("abc", %{username: "operator"}) ==
             {:rejected, 16, [:too_short, :insufficient_strength]}
  end