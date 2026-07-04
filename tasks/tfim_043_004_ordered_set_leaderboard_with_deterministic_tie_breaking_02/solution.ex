  test "top is empty with no scores", %{board: board} do
    assert [] = OrderedLeaderboard.top(board, 5)
  end