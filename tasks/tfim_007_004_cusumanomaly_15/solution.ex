  test "frozen stream ignores further pushes and keeps samples at zero" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 5, threshold: 3.0, slack: 0.5)

    for v <- [10.0, 11.0, 9.0, 10.5, 9.5], do: CusumAnomaly.push(c, "s", v)

    first_batch = for _ <- 1..5, do: CusumAnomaly.push(c, "s", 20.0)
    assert {:alert, :upward_shift} in first_batch

    frozen = for _ <- 1..25, do: CusumAnomaly.push(c, "s", 20.0)
    assert Enum.all?(frozen, &(&1 == :warming_up))

    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.samples == 0
    assert info.mean == 0.0
    assert info.s_high == 0.0
    assert info.s_low == 0.0
  end