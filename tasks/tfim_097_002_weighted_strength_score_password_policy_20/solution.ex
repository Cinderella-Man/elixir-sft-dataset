  test "each character class contributes exactly 10 points on its own" do
    # Each password is 4 characters -> 4 * 2 = 8 length points, no bonus, and is far
    # from the username, so the score isolates the character-class contribution.
    ctx = %{username: "operator"}

    # uppercase only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("ABCD", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # lowercase only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("abcd", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # digits only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("1234", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # specials only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("#$%^", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # all four classes at the same length -> 8 + 40 = 48
    assert PasswordPolicy.evaluate("Ab3#", ctx) ==
             {:rejected, 48, [:too_short, :insufficient_strength]}
  end