  test ":max_length defaults to 128, so 128 chars pass and 129 are :too_long" do
    {:ok, pid} = PasswordPolicy.start_link([])

    at_limit = "Aa1!" <> String.duplicate("x", 124)
    over_limit = "Aa1!" <> String.duplicate("x", 125)

    assert String.length(at_limit) == 128
    assert String.length(over_limit) == 129

    assert PasswordPolicy.set_password(pid, "operator", at_limit) == :ok

    assert PasswordPolicy.set_password(pid, "operator", over_limit) ==
             {:error, [:too_long]}
  end