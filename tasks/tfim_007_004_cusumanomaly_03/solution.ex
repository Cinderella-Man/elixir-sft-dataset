  test "the warmup_samples-th push transitions to :normal with :ok" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 10.0)

    assert :warming_up = CusumAnomaly.push(c, "s", 1.0)
    assert :warming_up = CusumAnomaly.push(c, "s", 2.0)
    assert :warming_up = CusumAnomaly.push(c, "s", 3.0)

    # Fourth push is CUSUM-active and shouldn't alert with threshold 10
    assert :ok = CusumAnomaly.push(c, "s", 4.0)

    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.status == :normal
  end