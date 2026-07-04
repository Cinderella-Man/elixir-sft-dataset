  test "top(n) returns at most n players", %{board: board} do
    for i <- 1..10, do: CumulativeLeaderboard.add_points(board, "p:#{i}", i * 10)
    assert length(CumulativeLeaderboard.top(board, 3)) == 3
  end