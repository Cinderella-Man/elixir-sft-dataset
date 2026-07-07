  test "no lowercase" do
    result = PasswordPolicy.validate("ABC123!!", %{username: "user", require_lowercase: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_lowercase])
  end