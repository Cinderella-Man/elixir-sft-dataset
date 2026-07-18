  test "two boards do not share state" do
    {:ok, a} = SlidingWindowLeaderboard.new(:"swa_#{:erlang.unique_integer([:positive])}", 1000)
    {:ok, b} = SlidingWindowLeaderboard.new(:"swb_#{:erlang.unique_integer([:positive])}", 1000)
    SlidingWindowLeaderboard.record(a, "alice", 5, 10_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(b, "alice", 10_000)
  end