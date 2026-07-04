  test "rank returns 1-based position and score", %{board: board} do
    Leaderboard.submit_score(board, "alice", 300)
    Leaderboard.submit_score(board, "bob", 100)
    Leaderboard.submit_score(board, "carol", 200)

    assert {:ok, 1, 300} = Leaderboard.rank(board, "alice")
    assert {:ok, 2, 200} = Leaderboard.rank(board, "carol")
    assert {:ok, 3, 100} = Leaderboard.rank(board, "bob")
  end