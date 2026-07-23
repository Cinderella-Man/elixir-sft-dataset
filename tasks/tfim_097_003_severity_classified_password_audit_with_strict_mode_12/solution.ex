  test "a lowered :min_length accepts a password shorter than the default" do
    # "Ab1!" is length 4: below the default minimum of 8, but valid once
    # :min_length is overridden to 4, with every character class present.
    report = PasswordPolicy.audit("Ab1!", %{username: "operator", min_length: 4})

    assert report == %{status: :ok, errors: [], warnings: []}
  end