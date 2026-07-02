  test "too long" do
    result =
      PasswordPolicy.validate("Ab1!" <> String.duplicate("x", 200), %{
        username: "user",
        max_length: 20
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_long])
  end