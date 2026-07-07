  test "rejects a strong password that is too similar to the username" do
    # Differs from the username by one character -> Levenshtein distance 1 (<= 3).
    result =
      PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn3", %{username: "Zx9#mQpLwT7$vBn2"})

    assert result == {:rejected, 92, [:too_similar_to_username]}
  end