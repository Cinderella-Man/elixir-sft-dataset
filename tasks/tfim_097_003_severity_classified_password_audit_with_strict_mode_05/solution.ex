  test "common password is a blocking error" do
    report =
      PasswordPolicy.audit("Password1!", %{
        username: "operator",
        common_passwords: ["password1!"]
      })

    assert report == %{status: :error, errors: [:common_password], warnings: []}
  end