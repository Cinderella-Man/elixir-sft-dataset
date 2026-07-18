  test "prune deletes the event exactly at the cutoff but keeps cutoff+1", %{board: board} do
    # window 1000, prune at now = 10_000 -> cutoff 9_000
    :ok = SlidingWindowLeaderboard.record(board, "alice", 42, 9_000)
    :ok = SlidingWindowLeaderboard.record(board, "bob", 7, 9_001)

    assert 1 = SlidingWindowLeaderboard.prune(board, 10_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_000)
    assert {:ok, 7} = SlidingWindowLeaderboard.score(board, "bob", 10_000)
  end