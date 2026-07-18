  test "prune returns 0 and keeps every event when nothing has expired", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 5, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 9, 10_400)

    assert 0 = SlidingWindowLeaderboard.prune(board, 10_500)
    assert {:ok, 5} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert [{"bob", 9}, {"alice", 5}] = SlidingWindowLeaderboard.top(board, 5, 10_500)
    assert 0 = SlidingWindowLeaderboard.prune(board, 10_500)
  end