  test "reused password is a blocking error" do
    report =
      PasswordPolicy.audit("Secret9!x", %{
        username: "operator",
        previous_passwords: ["Secret9!x"]
      })

    assert report == %{status: :error, errors: [:reused_password], warnings: []}
  end