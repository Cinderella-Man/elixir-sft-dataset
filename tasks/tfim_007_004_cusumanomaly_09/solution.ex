  test "reset/2 clears the stream state" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 10.0)

    for v <- [1.0, 2.0, 3.0, 4.0], do: CusumAnomaly.push(c, "s", v)
    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.samples > 0

    :ok = CusumAnomaly.reset(c, "s")

    {:ok, info2} = CusumAnomaly.check(c, "s")
    assert info2.samples == 0
    assert info2.mean == 0.0
  end