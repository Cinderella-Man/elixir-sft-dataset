  test "password far from username is accepted" do
    result =
      PasswordPolicy.validate("Zx9#mQpL", %{
        username: "alice",
        max_username_similarity: 3
      })

    assert result == :ok
  end