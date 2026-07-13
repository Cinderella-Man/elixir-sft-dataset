  test ":min_length defaults to 8, so a 7-character password is :too_short" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "operator", "Ab1!xyz") ==
             {:error, [:too_short]}

    # The same password one character longer sits exactly on the bound.
    assert PasswordPolicy.set_password(pid, "operator", "Ab1!xyzw") == :ok
  end