  test "rank is 1-based competition ranking with shared ranks on ties", %{board: board} do
    CumulativeLeaderboard.add_points(board, "alice", 300)
    CumulativeLeaderboard.add_points(board, "bob", 300)
    CumulativeLeaderboard.add_points(board, "carol", 100)

    assert {:ok, 1, 300} = CumulativeLeaderboard.rank(board, "alice")
    assert {:ok, 1, 300} = CumulativeLeaderboard.rank(board, "bob")
    # two players tied at rank 1 -> next player is rank 3
    assert {:ok, 3, 100} = CumulativeLeaderboard.rank(board, "carol")
  end