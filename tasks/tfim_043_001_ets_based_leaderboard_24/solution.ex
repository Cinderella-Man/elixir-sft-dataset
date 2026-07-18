  test "writes from a foreign process are visible to a third process", %{board: board} do
    writer = Task.async(fn -> Leaderboard.submit_score(board, "carol", 77) end)
    assert :ok = Task.await(writer, 5_000)

    reader = Task.async(fn -> Leaderboard.rank(board, "carol") end)
    assert {:ok, 1, 77} = Task.await(reader, 5_000)
  end