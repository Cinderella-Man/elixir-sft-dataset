  test "phase and heartbeat for unknown names" do
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:nope)
    assert :ok = EscalatingWatchdog.heartbeat(:nope)
  end