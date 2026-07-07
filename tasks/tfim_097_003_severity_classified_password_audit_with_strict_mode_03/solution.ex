  test "warnings alone do not flip the status to error" do
    # "abcdefgh": length 8 (ok), lowercase only. Only advisory violations.
    report = PasswordPolicy.audit("abcdefgh", %{username: "operator"})

    assert report == %{
             status: :ok,
             errors: [],
             warnings: [:no_uppercase, :no_digit, :no_special]
           }
  end