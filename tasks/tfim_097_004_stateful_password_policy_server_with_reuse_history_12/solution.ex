  test "lowercase is required by default" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "operator", "ABC123!@") ==
             {:error, [:no_lowercase]}

    assert PasswordPolicy.history_count(pid, "operator") == 0
  end