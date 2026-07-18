  test "concurrent awards to the same player are not lost", %{board: board} do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> CumulativeLeaderboard.add_points(board, "p", 1) end) end)
    |> Enum.each(&Task.await/1)

    assert {:ok, 100} = CumulativeLeaderboard.total(board, "p")
  end