  test "submitting the same score is a no-op and keeps the score", %{board: board} do
    Leaderboard.submit_score(board, "alice", 100)
    Leaderboard.submit_score(board, "alice", 100)

    assert [{"alice", 100}] = Leaderboard.top(board, 1)
  end