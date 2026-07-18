  test "username similarity uses literal Levenshtein distance without case folding" do
    # Literal distance("ALICE1!x", "alice") == 8 (no character matches, lengths 8 vs 5),
    # which is strictly greater than the default threshold of 3, so the password passes.
    result = PasswordPolicy.validate("ALICE1!x", %{username: "alice"})

    assert result == :ok
  end