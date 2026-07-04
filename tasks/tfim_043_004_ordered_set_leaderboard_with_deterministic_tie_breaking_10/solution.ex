  test "rank 1 for sole player", %{board: board} do
    OrderedLeaderboard.submit_score(board, "solo", 42)
    assert {:ok, 1, 42} = OrderedLeaderboard.rank(board, "solo")
  end