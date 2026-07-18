  test "a drifted (previous-step) code is accepted when not yet consumed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)
    # window default 1 covers base-1
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == :ok
  end