  test "history is bounded by :history_size and evicts the oldest" do
    {:ok, pid} = PasswordPolicy.start_link(history_size: 2)

    assert PasswordPolicy.set_password(pid, "carol", "Aaa111!!x") == :ok
    assert PasswordPolicy.set_password(pid, "carol", "Bbb222!!x") == :ok
    assert PasswordPolicy.set_password(pid, "carol", "Ccc333!!x") == :ok

    # Only the two most recent (Ccc, Bbb) are remembered; Aaa has been evicted.
    assert PasswordPolicy.history_count(pid, "carol") == 2
    assert PasswordPolicy.set_password(pid, "carol", "Bbb222!!x") == {:error, [:reused_password]}
    assert PasswordPolicy.set_password(pid, "carol", "Aaa111!!x") == :ok
  end