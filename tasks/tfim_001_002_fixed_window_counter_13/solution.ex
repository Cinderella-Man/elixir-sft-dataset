  test "registers under :name and serves calls via the registered name" do
    name = :fixed_window_limiter_named_test

    {:ok, pid} =
      FixedWindowLimiter.start_link(
        name: name,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert Process.whereis(name) == pid
    assert {:ok, 0} = FixedWindowLimiter.check(name, "k", 1, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(name, "k", 1, 1_000)
  end