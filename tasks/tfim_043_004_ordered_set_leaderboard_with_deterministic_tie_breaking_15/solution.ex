  test "resubmitting the exact same score does not re-timestamp arrival", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)

    # equal is not "strictly higher", so alice must keep her earlier arrival slot
    OrderedLeaderboard.submit_score(board, "alice", 100)

    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100} = OrderedLeaderboard.rank(board, "bob")
  end