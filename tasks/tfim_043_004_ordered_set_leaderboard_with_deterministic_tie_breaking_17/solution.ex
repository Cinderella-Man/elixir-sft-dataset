  test "top returns every player when n exceeds the population", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 30)
    OrderedLeaderboard.submit_score(board, "bob", 20)

    assert [{"alice", 30}, {"bob", 20}] = OrderedLeaderboard.top(board, 50)
    assert [{"alice", 30}] = OrderedLeaderboard.top(board, 1)
  end