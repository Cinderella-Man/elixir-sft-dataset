  test "large distribution 1..10000 is exact" do
    start_server([])

    for v <- 1..10_000, do: Percentile.record(:big, v)

    assert {:ok, 5_000} = Percentile.query(:big, 0.50)
    assert {:ok, 9_500} = Percentile.query(:big, 0.95)
    assert {:ok, 9_900} = Percentile.query(:big, 0.99)
    assert {:ok, 10_000} = Percentile.query(:big, 1.0)
  end