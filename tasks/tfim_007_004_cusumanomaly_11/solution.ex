  test "alerts in one stream don't affect another" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 5, threshold: 3.0)

    for _ <- 1..5, do: CusumAnomaly.push(c, "a", 10.0)
    for _ <- 1..5, do: CusumAnomaly.push(c, "b", 100.0)

    # Push a shift to "a" only
    for _ <- 1..20, do: CusumAnomaly.push(c, "a", 20.0)

    {:ok, info_b} = CusumAnomaly.check(c, "b")
    # "b" mean should still be near 100
    assert close_to(info_b.mean, 100.0, 1.0)
  end