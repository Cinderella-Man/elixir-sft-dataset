  test "require_uppercase defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("abcdefg1!", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_uppercase])
  end