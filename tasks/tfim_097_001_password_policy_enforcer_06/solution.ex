  test "no digit" do
    result = PasswordPolicy.validate("Abcdefg!", %{username: "user", require_digit: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_digit])
  end