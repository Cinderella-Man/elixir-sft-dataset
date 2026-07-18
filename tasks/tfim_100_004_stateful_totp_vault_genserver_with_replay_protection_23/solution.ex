  test "start_link/1 registers the process under :name and serves calls through it" do
    name = :"totp_vault_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = TOTPVault.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid

    # The registered name is a usable server reference for the whole API.
    assert {:ok, secret} = TOTPVault.register(name, "alice")
    assert {:ok, ^secret} = TOTPVault.secret(name, "alice")
    assert {:ok, code} = TOTPVault.current_code(name, "alice", time: 90_000)
    assert TOTPVault.consume(name, "alice", code, time: 90_000) == :ok
    assert TOTPVault.consume(name, "alice", code, time: 90_000) == {:error, :replayed}
  end