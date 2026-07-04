  test "after an alert, stream state is fully reset" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 5, threshold: 3.0, slack: 0.5)

    # Warmup
    for _ <- 1..5, do: CusumAnomaly.push(c, "s", 10.0)

    # Trigger
    {:alert, _} =
      Enum.find(
        for(_ <- 1..50, do: CusumAnomaly.push(c, "s", 20.0)),
        &match?({:alert, _}, &1)
      )

    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.samples == 0
    assert info.mean == 0.0
    assert info.stddev == 0.0
    assert info.s_high == 0.0
    assert info.s_low == 0.0
    assert info.status == :warming_up
  end