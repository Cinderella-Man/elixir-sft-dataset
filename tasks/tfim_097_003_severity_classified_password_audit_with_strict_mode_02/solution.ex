  test "weak short password splits into a blocking error and advisory warnings" do
    report = PasswordPolicy.audit("abc", %{username: "operator"})

    assert report == %{
             status: :error,
             errors: [:too_short],
             warnings: [:no_uppercase, :no_digit, :no_special]
           }
  end