  test "a zero-point award registers the player with a total of zero", %{board: board} do
    assert {:ok, 0} = CumulativeLeaderboard.add_points(board, "alice", 0)
    assert {:ok, 0} = CumulativeLeaderboard.total(board, "alice")
    assert {:ok, 1, 0} = CumulativeLeaderboard.rank(board, "alice")
  end