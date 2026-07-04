  test "submitting a higher score updates the stored score", %{board: board} do
    Leaderboard.submit_score(board, "alice", 100)
    Leaderboard.submit_score(board, "alice", 250)

    assert [{"alice", 250}] = Leaderboard.top(board, 1)
  end