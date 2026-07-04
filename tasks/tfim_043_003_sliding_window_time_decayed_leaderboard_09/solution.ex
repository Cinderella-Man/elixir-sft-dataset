  test "rank uses competition ranking over active scores", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 50, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_000)
    SlidingWindowLeaderboard.record(board, "carol", 10, 10_000)

    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "alice", 10_500)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "bob", 10_500)
    assert {:ok, 3, 10} = SlidingWindowLeaderboard.rank(board, "carol", 10_500)
  end