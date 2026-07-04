  test "top is sorted by score descending", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 300)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 200)

    assert [{"alice", 300}, {"carol", 200}, {"bob", 100}] = OrderedLeaderboard.top(board, 3)
  end