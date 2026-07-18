  test "the :name option registers the process for calls by name", %{ladder: ladder} do
    name = :penalty_limiter_named_process

    {:ok, _} =
      PenaltyLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    assert {:ok, 0} = PenaltyLimiter.check(name, "k", 1, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(name, "k", 1, 1_000, ladder)
  end