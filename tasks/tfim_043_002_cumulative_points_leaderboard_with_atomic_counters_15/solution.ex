  test "top returns every player when n exceeds the player count", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", 30)
    CumulativeLeaderboard.add_points(board, "bob", 10)

    assert [{"alice", 30}, {"bob", 10}] == CumulativeLeaderboard.top(board, 25)
  end