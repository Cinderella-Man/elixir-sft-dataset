  test "top returns all players when n exceeds player count", %{board: board} do
    Leaderboard.submit_score(board, "alice", 50)
    Leaderboard.submit_score(board, "bob", 80)

    result = Leaderboard.top(board, 100)
    assert length(result) == 2
  end