  test "top returns players sorted by score descending", %{board: board} do
    Leaderboard.submit_score(board, "alice", 300)
    Leaderboard.submit_score(board, "bob", 100)
    Leaderboard.submit_score(board, "carol", 200)

    assert [{"alice", 300}, {"carol", 200}, {"bob", 100}] = Leaderboard.top(board, 3)
  end