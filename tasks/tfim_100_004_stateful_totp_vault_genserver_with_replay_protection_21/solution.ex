  test "window: 2 widens acceptance to steps base-2 and base+2", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "ahead")
    {:ok, _} = TOTPVault.register(v, "behind")
    t = 90_000

    {:ok, ahead} = TOTPVault.current_code(v, "ahead", time: t + 60)
    {:ok, behind} = TOTPVault.current_code(v, "behind", time: t - 60)

    # Separate accounts: consuming one step must not replay-block the other.
    assert TOTPVault.consume(v, "ahead", ahead, time: t, window: 2) == :ok
    assert TOTPVault.consume(v, "behind", behind, time: t, window: 2) == :ok
  end