  test "record accepts float points and they sum into the active score", %{board: board} do
    assert :ok = SlidingWindowLeaderboard.record(board, "alice", 1.5, 10_000)
    assert :ok = SlidingWindowLeaderboard.record(board, "alice", 2.25, 10_100)

    assert {:ok, 3.75} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert [{"alice", 3.75}] = SlidingWindowLeaderboard.top(board, 3, 10_500)

    assert_raise FunctionClauseError, fn ->
      SlidingWindowLeaderboard.record(board, "alice", "five", 10_000)
    end
  end