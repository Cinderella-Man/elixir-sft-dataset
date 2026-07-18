  test "large number of players ranked correctly", %{board: board} do
    for i <- 1..1_000, do: OrderedLeaderboard.submit_score(board, "player:#{i}", i)
    assert [{"player:1000", 1_000}] = OrderedLeaderboard.top(board, 1)
    assert {:ok, 1, 1_000} = OrderedLeaderboard.rank(board, "player:1000")
    assert {:ok, 1_000, 1} = OrderedLeaderboard.rank(board, "player:1")
  end