  test "common password is case-insensitive" do
    # "PASSWORD1!" matches the common list case-insensitively AND has no lowercase
    # letter (require_lowercase defaults to true), so both violations fire.
    result =
      PasswordPolicy.validate("PASSWORD1!", %{
        username: "user",
        common_passwords: ["password1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password, :no_lowercase])
  end