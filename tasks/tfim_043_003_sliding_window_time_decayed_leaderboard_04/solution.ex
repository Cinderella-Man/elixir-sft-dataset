  test "expired events fall out of the window", %{board: board} do
    # window 1000, query at 10_500 -> cutoff 9_500
    SlidingWindowLeaderboard.record(board, "alice", 100, 9_000)
    SlidingWindowLeaderboard.record(board, "alice", 3, 10_000)
    assert {:ok, 3} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end