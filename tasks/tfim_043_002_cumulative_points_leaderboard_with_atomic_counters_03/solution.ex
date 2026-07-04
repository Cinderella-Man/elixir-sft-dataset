  test "first award initializes from zero", %{board: board} do
    assert {:ok, 10} = CumulativeLeaderboard.add_points(board, "alice", 10)
    assert {:ok, 10} = CumulativeLeaderboard.total(board, "alice")
  end