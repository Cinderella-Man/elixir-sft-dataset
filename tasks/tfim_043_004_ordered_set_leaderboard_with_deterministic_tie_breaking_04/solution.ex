  test "top(n) caps results and picks the highest", %{board: board} do
    for i <- 1..10, do: OrderedLeaderboard.submit_score(board, "p:#{i}", i * 10)
    assert [{"p:10", 100}, {"p:9", 90}, {"p:8", 80}] = OrderedLeaderboard.top(board, 3)
  end