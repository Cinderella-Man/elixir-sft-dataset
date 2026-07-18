  test "concurrent submits from many processes all land on the board", %{board: board} do
    players = for i <- 1..50, do: "concurrent:#{i}"

    players
    |> Enum.map(fn player ->
      Task.async(fn -> Leaderboard.submit_score(board, player, 10) end)
    end)
    |> Enum.each(fn task -> assert :ok = Task.await(task, 10_000) end)

    assert length(Leaderboard.top(board, 100)) == 50

    for player <- players do
      assert {:ok, rank, 10} = Leaderboard.rank(board, player)
      assert is_integer(rank) and rank >= 1
    end
  end