  test "a player whose active events sum to zero is found, not :not_found", %{board: board} do
    :ok = SlidingWindowLeaderboard.record(board, "zed", 0, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "nel", 5, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "nel", -5, 10_100)

    assert {:ok, 0} = SlidingWindowLeaderboard.score(board, "zed", 10_500)
    assert {:ok, 0} = SlidingWindowLeaderboard.score(board, "nel", 10_500)
    assert {:ok, 1, 0} = SlidingWindowLeaderboard.rank(board, "zed", 10_500)
    assert {"zed", 0} in SlidingWindowLeaderboard.top(board, 5, 10_500)
  end