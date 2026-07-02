  test "fewer than warmup_samples pushes return :warming_up" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 5, threshold: 3.0)

    for v <- [1, 2, 3, 4] do
      assert :warming_up = CusumAnomaly.push(c, "s", v)
    end

    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.status == :warming_up
    assert info.samples == 4
  end