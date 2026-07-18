  test "a process other than the creator can read top and rank", %{board: board} do
    Leaderboard.submit_score(board, "alice", 300)
    Leaderboard.submit_score(board, "bob", 100)

    reader =
      Task.async(fn ->
        {Leaderboard.top(board, 2), Leaderboard.rank(board, "bob"),
         Leaderboard.rank(board, "ghost")}
      end)

    assert {[{"alice", 300}, {"bob", 100}], {:ok, 2, 100}, {:error, :not_found}} =
             Task.await(reader, 5_000)
  end