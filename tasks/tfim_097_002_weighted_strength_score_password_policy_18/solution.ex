  test "a custom min_length rejects a password that clears the score threshold" do
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92, which is well above the
    # default min_score of 60. The hard length rule must still fire, and it must be the
    # only reason reported.
    result =
      PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn2", %{username: "operator", min_length: 20})

    assert result == {:rejected, 92, [:too_short]}
  end