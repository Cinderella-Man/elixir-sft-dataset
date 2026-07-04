  test "score is :not_found for unknown player", %{board: board} do
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "ghost", 10_000)
  end