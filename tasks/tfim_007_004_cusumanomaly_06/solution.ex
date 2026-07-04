  test "sustained upward shift triggers :upward_shift alert" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 10, threshold: 3.0, slack: 0.5)

    # Warmup with values around 10 with small variance
    for v <- [10.0, 10.1, 9.9, 10.2, 9.8, 10.0, 10.1, 9.9, 10.0, 10.1] do
      CusumAnomaly.push(c, "s", v)
    end

    # Jump to 20.0 and stay there
    outcomes = for _ <- 1..20, do: CusumAnomaly.push(c, "s", 20.0)

    assert Enum.any?(outcomes, &(&1 == {:alert, :upward_shift}))
  end