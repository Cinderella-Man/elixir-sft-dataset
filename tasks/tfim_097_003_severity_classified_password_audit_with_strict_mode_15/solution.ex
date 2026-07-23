  test "disabling uppercase, digit, and special requirements suppresses their warnings" do
    # Lowercase-only password that would normally warn on the three missing
    # classes; disabling each requirement clears every warning.
    report =
      PasswordPolicy.audit("abcdefgh", %{
        username: "operator",
        require_uppercase: false,
        require_digit: false,
        require_special: false
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end