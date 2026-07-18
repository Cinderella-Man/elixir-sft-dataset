  test "count-based window drops oldest first" do
    start_server(max_samples: 3)

    Percentile.record(:c, 1)
    Percentile.record(:c, 2)
    Percentile.record(:c, 3)
    assert {:ok, 1} = Percentile.query(:c, 0.0)

    Percentile.record(:c, 4)
    # 1 dropped, window is [2,3,4]
    assert {:ok, 2} = Percentile.query(:c, 0.0)
    assert {:ok, 4} = Percentile.query(:c, 1.0)
  end