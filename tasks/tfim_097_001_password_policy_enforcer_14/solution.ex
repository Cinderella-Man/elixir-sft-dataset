  test "valid password - all rules pass" do
    result =
      PasswordPolicy.validate("Tr0ub4dor&3", %{
        username: "alice",
        min_length: 8,
        max_length: 64,
        require_uppercase: true,
        require_lowercase: true,
        require_digit: true,
        require_special: true,
        common_passwords: ["password123"],
        previous_passwords: ["OldPass1!"]
      })

    assert result == :ok
  end