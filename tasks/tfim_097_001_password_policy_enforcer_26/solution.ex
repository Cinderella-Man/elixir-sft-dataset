  test "one case variant is a common password but not a reused password" do
    # The same stored string sits in both lists: :common_passwords compares
    # case-insensitively (so it matches), while :previous_passwords requires an exact
    # match (so it does not). Only :common_password may fire.
    result =
      PasswordPolicy.validate("Letmein1!", %{
        username: "user",
        common_passwords: ["LETMEIN1!"],
        previous_passwords: ["LETMEIN1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password])
  end