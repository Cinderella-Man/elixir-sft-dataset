  test "default min_length of 8 accepts an 8-character password but rejects a 7-character one" do
    # "Ab3#efgh": len 8 -> 16, all 4 classes -> 40, score 56. Length 8 is NOT below the
    # default hard minimum of 8, so :too_short must be absent (only the score fails).
    assert PasswordPolicy.evaluate("Ab3#efgh", %{username: "operator"}) ==
             {:rejected, 56, [:insufficient_strength]}

    # "Ab3#efg": len 7 -> 14, all 4 classes -> 40, score 54. Length 7 IS below 8 -> :too_short.
    assert PasswordPolicy.evaluate("Ab3#efg", %{username: "operator"}) ==
             {:rejected, 54, [:too_short, :insufficient_strength]}
  end