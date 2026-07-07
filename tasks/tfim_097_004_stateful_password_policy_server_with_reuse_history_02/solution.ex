  test "accepts a strong new password and records it in history" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "alice", "Tr0ub4dor&3") == :ok
    assert PasswordPolicy.history_count(pid, "alice") == 1
  end