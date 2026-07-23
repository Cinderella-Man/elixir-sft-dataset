  test "disabling the lowercase requirement suppresses its warning" do
    # Uppercase-only password: with the lowercase, digit, and special
    # requirements disabled, no warning remains.
    report =
      PasswordPolicy.audit("ABCDEFGH", %{
        username: "operator",
        require_lowercase: false,
        require_digit: false,
        require_special: false
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end