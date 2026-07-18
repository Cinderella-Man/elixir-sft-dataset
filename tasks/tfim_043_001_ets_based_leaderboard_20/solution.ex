  test "negative scores are valid and ranked correctly", %{board: board} do
    Leaderboard.submit_score(board, "alice", -10)
    Leaderboard.submit_score(board, "bob", -50)
    Leaderboard.submit_score(board, "carol", 0)

    assert [{"carol", 0}, {"alice", -10}, {"bob", -50}] = Leaderboard.top(board, 3)
    assert {:ok, 1, 0} = Leaderboard.rank(board, "carol")
    assert {:ok, 3, -50} = Leaderboard.rank(board, "bob")
  end