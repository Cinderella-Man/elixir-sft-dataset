  test "negative running totals are valid", %{board: board} do
    assert {:ok, -8} = CumulativeLeaderboard.add_points(board, "alice", -8)
    assert {:ok, 1, -8} = CumulativeLeaderboard.rank(board, "alice")
  end