  test "window: 0 narrows acceptance to the base step alone", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    # The neighbouring codes must be rejected purely for sitting outside a
    # zero-width window, so pick a base where neither equals the base code.
    t =
      Enum.find(1..5, fn candidate ->
        [_, prev, current, next, _] = codes_around(v, "alice", candidate * 90_000)
        current not in [prev, next]
      end) * 90_000

    [_, prev, current, next, _] = codes_around(v, "alice", t)

    assert TOTPVault.consume(v, "alice", next, time: t, window: 0) == {:error, :invalid}
    assert TOTPVault.consume(v, "alice", prev, time: t, window: 0) == {:error, :invalid}
    assert TOTPVault.consume(v, "alice", current, time: t, window: 0) == :ok
  end