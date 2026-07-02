  test "p0 returns the min and p100 returns the max" do
    start_server([])

    for v <- 1..100, do: Percentile.record(:d, v)

    assert {:ok, 1} = Percentile.query(:d, 0.0)
    assert {:ok, 100} = Percentile.query(:d, 1.0)
  end