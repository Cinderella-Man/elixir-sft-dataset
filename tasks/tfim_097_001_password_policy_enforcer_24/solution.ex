  test "require_special defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("Abcdef12", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_special])
  end