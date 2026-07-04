  test "different player id types are independent", %{board: board} do
    CumulativeLeaderboard.add_points(board, "1", 100)
    CumulativeLeaderboard.add_points(board, 1, 200)
    CumulativeLeaderboard.add_points(board, :one, 300)

    assert {:ok, 300} = CumulativeLeaderboard.total(board, :one)
    assert {:ok, 200} = CumulativeLeaderboard.total(board, 1)
    assert {:ok, 100} = CumulativeLeaderboard.total(board, "1")
  end