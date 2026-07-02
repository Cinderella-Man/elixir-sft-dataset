  test "p50/p95/p99 over 1..100 match nearest-rank" do
    start_server([])

    for v <- 1..100, do: assert :ok = Percentile.record(:d, v)

    assert {:ok, 50} = Percentile.query(:d, 0.50)
    assert {:ok, 95} = Percentile.query(:d, 0.95)
    assert {:ok, 99} = Percentile.query(:d, 0.99)
  end