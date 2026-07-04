  test "top(n) caps the result", %{board: board} do
    for i <- 1..6, do: SlidingWindowLeaderboard.record(board, "p:#{i}", i, 10_000)
    assert length(SlidingWindowLeaderboard.top(board, 3, 10_500)) == 3
  end