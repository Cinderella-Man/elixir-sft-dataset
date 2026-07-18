  test "valid with no optional rules enabled" do
    result =
      PasswordPolicy.validate("anything", %{
        username: "bob",
        min_length: 1,
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      })

    assert result == :ok
  end