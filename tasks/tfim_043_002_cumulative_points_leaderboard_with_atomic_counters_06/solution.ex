  test "top returns empty list when no scores", %{board: board} do
    assert [] = CumulativeLeaderboard.top(board, 5)
  end