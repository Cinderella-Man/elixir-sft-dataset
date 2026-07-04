  test "ranks are unique ordinals even on ties", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 50)

    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100} = OrderedLeaderboard.rank(board, "bob")
    assert {:ok, 3, 50} = OrderedLeaderboard.rank(board, "carol")
  end