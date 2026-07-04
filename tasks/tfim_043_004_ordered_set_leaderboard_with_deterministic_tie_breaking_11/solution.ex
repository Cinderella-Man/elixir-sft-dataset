  test "zero and negative scores rank correctly", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", -10)
    OrderedLeaderboard.submit_score(board, "bob", -50)
    OrderedLeaderboard.submit_score(board, "carol", 0)

    assert [{"carol", 0}, {"alice", -10}, {"bob", -50}] = OrderedLeaderboard.top(board, 3)
    assert {:ok, 1, 0} = OrderedLeaderboard.rank(board, "carol")
    assert {:ok, 3, -50} = OrderedLeaderboard.rank(board, "bob")
  end