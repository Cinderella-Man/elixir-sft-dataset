  test "valid password - username similarity just outside threshold" do
    result =
      PasswordPolicy.validate("userXYZW1!", %{
        username: "user",
        require_uppercase: true,
        require_lowercase: false,
        max_username_similarity: 3
      })

    assert result == :ok
  end