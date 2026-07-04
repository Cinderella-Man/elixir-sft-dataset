  test "submitting a lower score does not overwrite a higher one", %{board: board} do
    Leaderboard.submit_score(board, "alice", 500)
    Leaderboard.submit_score(board, "alice", 50)

    assert [{"alice", 500}] = Leaderboard.top(board, 1)
  end