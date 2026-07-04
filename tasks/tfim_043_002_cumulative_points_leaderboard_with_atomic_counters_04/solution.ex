  test "points accumulate across awards", %{board: board} do
    assert {:ok, 10} = CumulativeLeaderboard.add_points(board, "alice", 10)
    assert {:ok, 15} = CumulativeLeaderboard.add_points(board, "alice", 5)
    assert {:ok, 12} = CumulativeLeaderboard.add_points(board, "alice", -3)
    assert {:ok, 12} = CumulativeLeaderboard.total(board, "alice")
  end