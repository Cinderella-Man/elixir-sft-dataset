  test "top(n) returns at most n players", %{board: board} do
    for i <- 1..10 do
      Leaderboard.submit_score(board, "player:#{i}", i * 10)
    end

    result = Leaderboard.top(board, 3)
    assert length(result) == 3

    # Should be the three highest scores
    [{_, s1}, {_, s2}, {_, s3}] = result
    assert s1 >= s2
    assert s2 >= s3
    assert s1 == 100
    assert s2 == 90
    assert s3 == 80
  end