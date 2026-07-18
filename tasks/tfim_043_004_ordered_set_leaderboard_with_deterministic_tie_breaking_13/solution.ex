  test "two boards do not share state" do
    {:ok, a} = OrderedLeaderboard.new(:"oba_#{:erlang.unique_integer([:positive])}")
    {:ok, b} = OrderedLeaderboard.new(:"obb_#{:erlang.unique_integer([:positive])}")
    OrderedLeaderboard.submit_score(a, "alice", 999)
    assert {:error, :not_found} = OrderedLeaderboard.rank(b, "alice")
    assert [] = OrderedLeaderboard.top(b, 5)
  end