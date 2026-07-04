  test "reaching a new high re-timestamps arrival for tie-breaking", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    # alice and bob tied at 100, alice first -> alice ahead
    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)

    # bob jumps ahead, then both settle at 200 with bob reaching it first
    OrderedLeaderboard.submit_score(board, "bob", 200)
    OrderedLeaderboard.submit_score(board, "alice", 200)
    assert [{"bob", 200}, {"alice", 200}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 200} = OrderedLeaderboard.rank(board, "bob")
    assert {:ok, 2, 200} = OrderedLeaderboard.rank(board, "alice")
  end