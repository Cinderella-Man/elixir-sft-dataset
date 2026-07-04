  test "top returns players sorted by total descending", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", 100)
    CumulativeLeaderboard.add_points(board, "bob", 40)
    CumulativeLeaderboard.add_points(board, "bob", 40)
    CumulativeLeaderboard.add_points(board, "carol", 50)

    assert [{"alice", 100}, {"bob", 80}, {"carol", 50}] = CumulativeLeaderboard.top(board, 3)
  end