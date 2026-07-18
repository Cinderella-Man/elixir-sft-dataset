  test "cleanup on a fresh empty state is a harmless no-op", %{rl: rl} do
    send(rl, :cleanup)
    send(rl, :cleanup)

    # An untouched key still behaves like a brand-new key after empty sweeps.
    assert {:ok, 4} = RateLimiter.check(rl, "brand:new", 5, 1_000)
    assert Process.alive?(rl)
  end