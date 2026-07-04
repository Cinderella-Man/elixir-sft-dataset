  test "total is :error for unknown player", %{board: board} do
    assert {:error, :not_found} = CumulativeLeaderboard.total(board, "ghost")
  end