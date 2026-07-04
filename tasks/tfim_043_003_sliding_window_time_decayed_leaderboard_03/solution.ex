  test "active events sum within the window", %{board: board} do
    :ok = SlidingWindowLeaderboard.record(board, "alice", 5, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "alice", 7, 10_200)
    assert {:ok, 12} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end