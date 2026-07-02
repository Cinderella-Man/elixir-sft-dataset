  test "no uppercase" do
    result = PasswordPolicy.validate("abc123!!", %{username: "user", require_uppercase: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_uppercase])
  end