  test "float samples are supported" do
    start_server([])

    for v <- [1.5, 2.5, 3.5, 4.5], do: Percentile.record(:f, v)

    assert {:ok, 1.5} = Percentile.query(:f, 0.0)
    assert {:ok, 4.5} = Percentile.query(:f, 1.0)
    # ceil(0.5*4) = 2 -> s_2 = 2.5
    assert {:ok, 2.5} = Percentile.query(:f, 0.50)
  end