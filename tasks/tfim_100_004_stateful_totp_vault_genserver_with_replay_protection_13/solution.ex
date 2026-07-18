  test "after consuming the current step, an earlier step's code is :replayed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, current} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)

    assert TOTPVault.consume(v, "alice", current, time: 90_000) == :ok
    # prev belongs to step base-1 <= last consumed step base.
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == {:error, :replayed}
  end