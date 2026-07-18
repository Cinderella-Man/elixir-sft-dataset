  test "players with equal scores share the same rank", %{board: board} do
    # Two players tied at the top: neither has anyone above, so both are rank 1.
    Leaderboard.submit_score(board, "alice", 100)
    Leaderboard.submit_score(board, "bob", 100)

    assert {:ok, rank_a, 100} = Leaderboard.rank(board, "alice")
    assert {:ok, rank_b, 100} = Leaderboard.rank(board, "bob")
    assert rank_a == rank_b
    assert rank_a == 1
  end