  test "a later step's code still works after an earlier consumption", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, c1} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, c2} = TOTPVault.current_code(v, "alice", time: 90_030)

    assert TOTPVault.consume(v, "alice", c1, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", c2, time: 90_030) == :ok
  end