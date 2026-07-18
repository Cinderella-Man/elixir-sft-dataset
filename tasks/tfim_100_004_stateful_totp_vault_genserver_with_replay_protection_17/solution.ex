  test "current_code matches an independent RFC 6238 computation over 300 steps", %{vault: v} do
    {:ok, secret} = TOTPVault.register(v, "alice")

    for step <- 0..299 do
      time = step * 30
      assert {:ok, code} = TOTPVault.current_code(v, "alice", time: time)
      assert code == rfc6238_code(secret, time)
    end
  end