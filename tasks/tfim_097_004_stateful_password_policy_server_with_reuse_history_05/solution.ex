  test "policy violations are reported in canonical order and not recorded" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "operator", "abc") ==
             {:error, [:too_short, :no_uppercase, :no_digit, :no_special]}

    assert PasswordPolicy.history_count(pid, "operator") == 0
  end