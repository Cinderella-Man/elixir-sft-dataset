  test "common password" do
    result =
      PasswordPolicy.validate("Password1!", %{
        username: "user",
        common_passwords: ["password1!", "letmein"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password])
  end