  test "concurrent record calls are not lost", %{board: board} do
    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> SlidingWindowLeaderboard.record(board, "p", 1, 10_000) end)
    end)
    |> Enum.each(&Task.await/1)

    assert {:ok, 100} = SlidingWindowLeaderboard.score(board, "p", 10_500)
  end