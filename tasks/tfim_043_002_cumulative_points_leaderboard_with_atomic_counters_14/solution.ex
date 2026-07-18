  test "concurrent awards across many players are all correct", %{board: board} do
    for p <- 1..20 do
      1..50
      |> Enum.map(fn _ -> Task.async(fn -> CumulativeLeaderboard.add_points(board, p, 2) end) end)
      |> Enum.each(&Task.await/1)
    end

    for p <- 1..20 do
      assert {:ok, 100} = CumulativeLeaderboard.total(board, p)
    end
  end