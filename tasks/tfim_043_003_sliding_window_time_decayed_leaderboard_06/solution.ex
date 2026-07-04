  test "event exactly at the cutoff is expired", %{board: board} do
    # query at 10_000, window 1000 -> cutoff 9_000; event at 9_000 is expired
    SlidingWindowLeaderboard.record(board, "alice", 42, 9_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_000)

    # one millisecond later it is active
    SlidingWindowLeaderboard.record(board, "bob", 42, 9_001)
    assert {:ok, 42} = SlidingWindowLeaderboard.score(board, "bob", 10_000)
  end