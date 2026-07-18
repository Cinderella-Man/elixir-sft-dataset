  test "two boards do not share state" do
    {:ok, a} = CumulativeLeaderboard.new(:"cba_#{:erlang.unique_integer([:positive])}")
    {:ok, b} = CumulativeLeaderboard.new(:"cbb_#{:erlang.unique_integer([:positive])}")
    CumulativeLeaderboard.add_points(a, "alice", 5)
    assert {:error, :not_found} = CumulativeLeaderboard.total(b, "alice")
  end