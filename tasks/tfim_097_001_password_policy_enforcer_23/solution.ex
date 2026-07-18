  test "require_digit defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("Abcdefg!", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_digit])
  end