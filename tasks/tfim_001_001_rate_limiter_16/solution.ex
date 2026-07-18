  test "check/4 works through the registered name and the pid alike" do
    name = :rate_limiter_registered_name_test

    {:ok, pid} =
      RateLimiter.start_link(
        name: name,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    # Same process reached two ways: state accumulates across both call styles.
    assert {:ok, 4} = RateLimiter.check(name, "u", 5, 1_000)
    assert {:ok, 3} = RateLimiter.check(pid, "u", 5, 1_000)
  end