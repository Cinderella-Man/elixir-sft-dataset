  test "a rejected replay leaves the highest consumed step intact", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, current} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)

    assert TOTPVault.consume(v, "alice", current, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == {:error, :replayed}

    # The rejected attempt must not have lowered or cleared the stored step:
    # the base-step code stays spent, and a later step is still spendable.
    assert TOTPVault.consume(v, "alice", current, time: 90_000) == {:error, :replayed}
    {:ok, next} = TOTPVault.current_code(v, "alice", time: 90_030)
    assert TOTPVault.consume(v, "alice", next, time: 90_030) == :ok
  end