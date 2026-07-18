  test "default warmup_samples is 10 pushes" do
    {:ok, c} = CusumAnomaly.start_link()

    for _ <- 1..10, do: assert(:warming_up = CusumAnomaly.push(c, "s", 5.0))

    # The 11th push is the first CUSUM-active push (default warmup is 10).
    assert :ok = CusumAnomaly.push(c, "s", 5.0)
  end