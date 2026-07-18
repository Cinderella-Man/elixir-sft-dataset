  test "reset clears the post-alert freeze so the stream re-learns" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 3.0, slack: 0.5)

    for v <- [10.0, 11.0, 9.0], do: CusumAnomaly.push(c, "s", v)
    assert {:alert, :upward_shift} = CusumAnomaly.push(c, "s", 20.0)

    :ok = CusumAnomaly.reset(c, "s")

    assert :warming_up = CusumAnomaly.push(c, "s", 1.0)
    assert :warming_up = CusumAnomaly.push(c, "s", 2.0)
    assert :warming_up = CusumAnomaly.push(c, "s", 3.0)

    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.samples == 3
    assert close_to(info.mean, 2.0)
  end