  test "higher score overwrites, lower is a no-op", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "alice", 250)
    OrderedLeaderboard.submit_score(board, "alice", 50)
    assert [{"alice", 250}] = OrderedLeaderboard.top(board, 1)
    assert {:ok, 1, 250} = OrderedLeaderboard.rank(board, "alice")
  end