  test "reused password" do
    result =
      PasswordPolicy.validate("Correct1!", %{
        username: "user",
        previous_passwords: ["OldPass9#", "Correct1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:reused_password])
  end