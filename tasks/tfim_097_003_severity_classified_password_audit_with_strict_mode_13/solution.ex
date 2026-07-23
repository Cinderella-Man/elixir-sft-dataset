  test "a password longer than :max_length is a blocking :too_long error" do
    # Length 8 clears the default minimum but exceeds the overridden maximum
    # of 4, so the only violation is the blocking :too_long rule.
    report = PasswordPolicy.audit("Ab1!wxyz", %{username: "operator", max_length: 4})

    assert report == %{status: :error, errors: [:too_long], warnings: []}
  end