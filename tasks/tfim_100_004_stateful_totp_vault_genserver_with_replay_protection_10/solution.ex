  test "consume accepts an integer code", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)
    assert TOTPVault.consume(v, "alice", String.to_integer(code), time: 90_000) == :ok
  end