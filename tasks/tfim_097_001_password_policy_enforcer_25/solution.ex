  test "reuse comparison is exact, so a case variant of a previous password passes" do
    # Reuse rejects only an exact match against :previous_passwords. "COrrect1!" differs
    # from the stored "Correct1!" by letter case alone, so it is not a reuse; it still
    # satisfies every character-class rule and is far from the username.
    case_variant =
      PasswordPolicy.validate("COrrect1!", %{
        username: "user",
        previous_passwords: ["Correct1!"]
      })

    assert case_variant == :ok

    # The exact same string, on the other hand, is a reuse.
    exact =
      PasswordPolicy.validate("Correct1!", %{
        username: "user",
        previous_passwords: ["Correct1!"]
      })

    assert Enum.sort(violations(exact)) == Enum.sort([:reused_password])
  end