  test "score reflects the window sliding forward over time", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 10, 10_000)
    SlidingWindowLeaderboard.record(board, "alice", 20, 10_800)

    assert {:ok, 30} = SlidingWindowLeaderboard.score(board, "alice", 10_900)
    # advance so the first event (10_000) has expired: cutoff at 11_100 = 10_100
    assert {:ok, 20} = SlidingWindowLeaderboard.score(board, "alice", 11_100)
  end