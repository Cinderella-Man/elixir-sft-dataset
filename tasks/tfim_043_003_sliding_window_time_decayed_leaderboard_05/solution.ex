  test "player with only expired events is :not_found", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 100, 1_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end