  test "consume without a :window option accepts only steps base-1..base+1", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    # The base±2 codes must be rejected purely for sitting OUTSIDE the default
    # window, so pick a base where neither collides with any in-window code
    # (distinct steps can produce the same 6-digit code by chance).
    t =
      Enum.find(1..5, fn candidate ->
        [far_past, prev, current, next, far_future] =
          codes_around(v, "alice", candidate * 90_000)

        far_past not in [prev, current, next] and far_future not in [prev, current, next]
      end) * 90_000

    [far_past, _prev, _current, _next, far_future] = codes_around(v, "alice", t)

    assert TOTPVault.consume(v, "alice", far_future, time: t) == {:error, :invalid}
    assert TOTPVault.consume(v, "alice", far_past, time: t) == {:error, :invalid}
  end