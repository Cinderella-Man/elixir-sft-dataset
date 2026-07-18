  test "add_points refuses non-integer point values", %{board: board} do
    assert_raise FunctionClauseError, fn ->
      CumulativeLeaderboard.add_points(board, "alice", 1.5)
    end

    assert_raise FunctionClauseError, fn ->
      CumulativeLeaderboard.add_points(board, "alice", "5")
    end

    assert {:error, :not_found} = CumulativeLeaderboard.total(board, "alice")
  end