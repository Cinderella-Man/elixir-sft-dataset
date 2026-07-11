  test "series are completely independent" do
    start_server([])

    for v <- 1..100, do: Percentile.record(:a, v)
    for v <- 200..209, do: Percentile.record(:b, v)

    assert {:ok, 50} = Percentile.query(:a, 0.50)
    assert {:ok, 200} = Percentile.query(:b, 0.0)
    assert {:ok, 209} = Percentile.query(:b, 1.0)

    Percentile.reset(:a)
    assert {:error, :empty} = Percentile.query(:a, 0.5)
    # b untouched
    assert {:ok, 209} = Percentile.query(:b, 1.0)
  end