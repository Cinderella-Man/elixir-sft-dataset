  test "rank recomputes as the window slides and leaders expire", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 100, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_800)
    SlidingWindowLeaderboard.record(board, "carol", 50, 10_800)

    assert {:ok, 1, 100} = SlidingWindowLeaderboard.rank(board, "alice", 10_900)
    assert {:ok, 2, 50} = SlidingWindowLeaderboard.rank(board, "bob", 10_900)

    # cutoff at 11_100 = 10_100, so alice's only event has expired
    assert {:error, :not_found} = SlidingWindowLeaderboard.rank(board, "alice", 11_100)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "bob", 11_100)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "carol", 11_100)
  end