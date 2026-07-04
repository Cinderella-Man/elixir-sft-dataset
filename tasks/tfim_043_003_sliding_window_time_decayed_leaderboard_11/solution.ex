  test "prune deletes expired events and returns the count", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 1, 1_000)
    SlidingWindowLeaderboard.record(board, "alice", 2, 2_000)
    SlidingWindowLeaderboard.record(board, "bob", 3, 10_000)

    # at now = 10_500 cutoff = 9_500, both of alice's events expired
    assert 2 = SlidingWindowLeaderboard.prune(board, 10_500)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert {:ok, 3} = SlidingWindowLeaderboard.score(board, "bob", 10_500)
  end