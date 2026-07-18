  test "require_* set to false skips exactly the matching character-class checks" do
    {:ok, pid} =
      PasswordPolicy.start_link(
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      )

    # Digits only: no uppercase, no lowercase, no special -- all four checks
    # are switched off, so this is accepted and recorded.
    assert PasswordPolicy.set_password(pid, "operator", "12345678") == :ok
    assert PasswordPolicy.history_count(pid, "operator") == 1
  end