  test "a stable signal around a mean never alerts" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 5, threshold: 5.0, slack: 0.5)

    # Warmup
    for _ <- 1..5, do: CusumAnomaly.push(c, "s", 100.0)

    # Stable signal with tiny fluctuations — should never alert
    import_random = fn -> :rand.uniform() * 0.01 end

    outcomes =
      for _ <- 1..500 do
        CusumAnomaly.push(c, "s", 100.0 + import_random.())
      end

    assert Enum.all?(outcomes, &(&1 == :ok))
  end