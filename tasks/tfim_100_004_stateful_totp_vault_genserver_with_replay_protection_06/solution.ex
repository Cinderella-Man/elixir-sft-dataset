  test "current_code is read-only and stable within a step", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, c1} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, c2} = TOTPVault.current_code(v, "alice", time: 90_029)
    assert c1 == c2
    assert byte_size(c1) == 6
    # Still consumable afterward — reading did not spend it.
    assert TOTPVault.consume(v, "alice", c1, time: 90_000) == :ok
  end