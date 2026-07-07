  test "rejects reuse of a remembered password without touching history" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == :ok
    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == {:error, [:reused_password]}
    assert PasswordPolicy.history_count(pid, "alice") == 1
  end