  test "re-consuming the same code returns :replayed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", code, time: 90_000) == {:error, :replayed}
  end