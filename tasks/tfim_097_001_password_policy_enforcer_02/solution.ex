  test "too short" do
    result = PasswordPolicy.validate("Ab1!", %{username: "user", min_length: 8})
    assert Enum.sort(violations(result)) == Enum.sort([:too_short])
  end