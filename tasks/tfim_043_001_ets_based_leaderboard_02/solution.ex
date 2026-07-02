  test "top returns empty list when no scores submitted", %{board: board} do
    assert [] = Leaderboard.top(board, 5)
  end