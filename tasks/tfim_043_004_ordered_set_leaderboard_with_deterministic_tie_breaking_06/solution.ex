  test "ties broken by who reached the score first", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 100)

    assert [{"alice", 100}, {"bob", 100}, {"carol", 100}] = OrderedLeaderboard.top(board, 3)
  end