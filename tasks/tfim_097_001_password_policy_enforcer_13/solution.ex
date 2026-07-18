  test "multiple violations: common + reused" do
    result =
      PasswordPolicy.validate("Letmein1!", %{
        username: "other",
        require_uppercase: false,
        require_digit: false,
        require_special: false,
        require_lowercase: false,
        common_passwords: ["letmein1!"],
        previous_passwords: ["Letmein1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password, :reused_password])
  end