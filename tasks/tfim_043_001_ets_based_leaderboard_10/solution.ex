  test "rank returns :error for unknown player", %{board: board} do
    assert {:error, :not_found} = Leaderboard.rank(board, "ghost")
  end