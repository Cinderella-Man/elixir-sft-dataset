  test "different id types are independent", %{board: board} do
    OrderedLeaderboard.submit_score(board, "1", 100)
    OrderedLeaderboard.submit_score(board, 1, 200)
    OrderedLeaderboard.submit_score(board, :one, 300)

    assert {:ok, 1, 300} = OrderedLeaderboard.rank(board, :one)
    assert {:ok, 2, 200} = OrderedLeaderboard.rank(board, 1)
    assert {:ok, 3, 100} = OrderedLeaderboard.rank(board, "1")
  end