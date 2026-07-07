  test "rejects a common password even when it scores at the threshold" do
    # "Password1!": len 10 -> 20, all 4 classes -> 40, score 60 (meets threshold),
    # but it is on the common list -> case-insensitive rejection.
    result =
      PasswordPolicy.evaluate("Password1!", %{
        username: "operator",
        common_passwords: ["password1!"]
      })

    assert result == {:rejected, 60, [:common_password]}
  end