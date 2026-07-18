  test "top sorts negative totals below zero and positive totals", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", -50)
    CumulativeLeaderboard.add_points(board, "bob", 0)
    CumulativeLeaderboard.add_points(board, "carol", 5)
    CumulativeLeaderboard.add_points(board, "carol", -20)

    assert [{"bob", 0}, {"carol", -15}, {"alice", -50}] == CumulativeLeaderboard.top(board, 3)
  end