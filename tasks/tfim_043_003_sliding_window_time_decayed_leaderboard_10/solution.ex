  test "rank is :not_found when the player has no active events", %{board: board} do
    assert {:error, :not_found} = SlidingWindowLeaderboard.rank(board, "ghost", 10_500)
  end