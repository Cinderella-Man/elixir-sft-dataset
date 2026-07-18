  test "racing submits for one player still keep the all-time highest", %{board: board} do
    # Interleaved submissions of the same score set from several processes:
    # a lost update (read-then-write without atomicity) would leave a score
    # lower than the maximum ever submitted.
    players = ["racer_a", "racer_b", "racer_c"]
    scores = Enum.to_list(1..200)

    for player <- players, _writer <- 1..6 do
      Task.async(fn ->
        for score <- Enum.shuffle(scores) do
          Leaderboard.submit_score(board, player, score)
        end

        :done
      end)
    end
    |> Enum.each(fn task -> assert :done = Task.await(task, 60_000) end)

    for player <- players do
      assert {:ok, 1, 200} = Leaderboard.rank(board, player)
    end

    assert length(Leaderboard.top(board, 10)) == 3
  end