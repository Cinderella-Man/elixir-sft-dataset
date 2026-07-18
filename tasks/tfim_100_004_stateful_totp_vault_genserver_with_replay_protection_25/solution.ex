  test "a spent step stays rejected later even under a much wider window", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok

    # At time 90_120 the base step is 3004, so window 5 spans steps 2999..3009
    # and therefore re-offers the already-spent step 3000.
    assert TOTPVault.consume(v, "alice", code, time: 90_120, window: 5) == {:error, :replayed}
  end