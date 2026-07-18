  test "the :name option registers the server so calls can be made through the name" do
    name = :password_policy_named_server_test
    {:ok, pid} = PasswordPolicy.start_link(name: name)

    assert Process.whereis(name) == pid

    # Both public calls must work through the registered name.
    assert PasswordPolicy.set_password(name, "alice", "Tr0ub4dor&3") == :ok
    assert PasswordPolicy.history_count(name, "alice") == 1

    # The name and the pid address the same server state.
    assert PasswordPolicy.set_password(pid, "alice", "Tr0ub4dor&3") ==
             {:error, [:reused_password]}
  end