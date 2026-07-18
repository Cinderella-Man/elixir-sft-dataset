  test "multiple violations: too short + no uppercase + no digit" do
    result =
      PasswordPolicy.validate("abc!", %{
        username: "other",
        min_length: 8,
        require_uppercase: true,
        require_digit: true,
        require_lowercase: true,
        require_special: true
      })

    expected = MapSet.new([:too_short, :no_uppercase, :no_digit])
    got = MapSet.new(violations(result))
    assert MapSet.subset?(expected, got)
  end