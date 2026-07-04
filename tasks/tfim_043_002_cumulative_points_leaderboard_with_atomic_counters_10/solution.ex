  test "rank returns :error for unknown player", %{board: board} do
    assert {:error, :not_found} = CumulativeLeaderboard.rank(board, "ghost")
  end