  test "a tie below a leader shares one rank behind that leader", %{board: board} do
    # Exactly one distinct higher score sits above the tie, so both tied
    # players occupy the same rank, one behind the leader.
    Leaderboard.submit_score(board, "leader", 300)
    Leaderboard.submit_score(board, "alice", 100)
    Leaderboard.submit_score(board, "bob", 100)

    assert {:ok, 1, 300} = Leaderboard.rank(board, "leader")

    assert {:ok, rank_a, 100} = Leaderboard.rank(board, "alice")
    assert {:ok, rank_b, 100} = Leaderboard.rank(board, "bob")
    assert rank_a == rank_b
    assert rank_a == 2
  end