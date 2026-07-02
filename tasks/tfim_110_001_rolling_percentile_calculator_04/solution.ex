  test "unsorted input is handled correctly" do
    start_server([])

    for v <- Enum.shuffle(1..10), do: Percentile.record(:d, v)

    assert {:ok, 1} = Percentile.query(:d, 0.0)
    assert {:ok, 10} = Percentile.query(:d, 1.0)
    # nearest-rank p50 of 10 samples: ceil(0.5*10) = 5 -> s_5 = 5
    assert {:ok, 5} = Percentile.query(:d, 0.50)
  end