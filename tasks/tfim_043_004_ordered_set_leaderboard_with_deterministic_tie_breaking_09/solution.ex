  test "rank is :not_found for unknown player", %{board: board} do
    assert {:error, :not_found} = OrderedLeaderboard.rank(board, "ghost")
  end