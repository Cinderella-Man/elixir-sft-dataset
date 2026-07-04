  test "sustained downward shift triggers :downward_shift alert" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 10, threshold: 3.0, slack: 0.5)

    for v <- [10.0, 10.1, 9.9, 10.2, 9.8, 10.0, 10.1, 9.9, 10.0, 10.1] do
      CusumAnomaly.push(c, "s", v)
    end

    outcomes = for _ <- 1..20, do: CusumAnomaly.push(c, "s", 2.0)

    assert Enum.any?(outcomes, &(&1 == {:alert, :downward_shift}))
  end