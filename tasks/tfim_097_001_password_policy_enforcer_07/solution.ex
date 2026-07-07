  test "no special character" do
    result = PasswordPolicy.validate("Abcdef12", %{username: "user", require_special: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_special])
  end