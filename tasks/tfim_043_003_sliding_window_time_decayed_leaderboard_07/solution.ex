  test "top excludes expired players and sorts descending", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 30, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_100)
    SlidingWindowLeaderboard.record(board, "carol", 999, 1_000)

    assert [{"bob", 50}, {"alice", 30}] = SlidingWindowLeaderboard.top(board, 5, 10_500)
  end