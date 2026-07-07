  test "strict mode promotes all warnings into errors and fails the status" do
    report = PasswordPolicy.audit("abcdefgh", %{username: "operator", strict: true})

    assert report == %{
             status: :error,
             errors: [:no_uppercase, :no_digit, :no_special],
             warnings: []
           }
  end