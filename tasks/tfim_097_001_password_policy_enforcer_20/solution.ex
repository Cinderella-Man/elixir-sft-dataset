  test "max_length defaults to 128 when the option is omitted" do
    too_long = "Aa1!" <> String.duplicate("x", 125)
    assert {:error, errs} = PasswordPolicy.validate(too_long, %{username: "someuser"})
    assert Enum.sort(errs) == Enum.sort([:too_long])

    at_limit = "Aa1!" <> String.duplicate("x", 124)
    assert PasswordPolicy.validate(at_limit, %{username: "someuser"}) == :ok
  end