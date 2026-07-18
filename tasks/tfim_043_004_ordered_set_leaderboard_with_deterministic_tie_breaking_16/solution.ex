  test "float and integer scores of equal value tie and break by arrival", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100.0)

    assert [{"alice", 100}, {"bob", 100.0}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100.0} = OrderedLeaderboard.rank(board, "bob")

    # 100.0 is not strictly higher than 100, so it must not move alice
    OrderedLeaderboard.submit_score(board, "alice", 100.0)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")

    OrderedLeaderboard.submit_score(board, "alice", 100.5)
    assert [{"alice", 100.5}, {"bob", 100.0}] = OrderedLeaderboard.top(board, 2)
  end