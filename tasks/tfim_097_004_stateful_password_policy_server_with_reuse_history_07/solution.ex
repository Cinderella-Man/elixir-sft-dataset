  test "per-user histories are independent" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == :ok
    # bob has never used it, so it is fine for bob...
    assert PasswordPolicy.set_password(pid, "bob", "Secret9!x") == :ok
    # ...but alice still cannot reuse her own.
    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == {:error, [:reused_password]}
  end