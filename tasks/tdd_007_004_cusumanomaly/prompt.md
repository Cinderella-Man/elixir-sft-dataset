# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
defmodule CusumAnomalyTest do
  use ExUnit.Case, async: false

  defp close_to(a, b, eps \\ 1.0e-9), do: abs(a - b) <= eps

  # -------------------------------------------------------
  # Warmup behavior
  # -------------------------------------------------------

  test "fewer than warmup_samples pushes return :warming_up" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 5, threshold: 3.0)

    for v <- [1, 2, 3, 4] do
      assert :warming_up = CusumAnomaly.push(c, "s", v)
    end

    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.status == :warming_up
    assert info.samples == 4
  end

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

  # -------------------------------------------------------
  # Welford's math
  # -------------------------------------------------------

  test "Welford mean matches the arithmetic mean over pushed values" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 1000, threshold: 1000.0)

    values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
    for v <- values, do: CusumAnomaly.push(c, "s", v)

    {:ok, info} = CusumAnomaly.check(c, "s")
    expected_mean = Enum.sum(values) / length(values)
    assert close_to(info.mean, expected_mean)

    # Population stddev of the classic Welford test input is 2.0.
    assert close_to(info.stddev, 2.0, 1.0e-9)
  end

  # -------------------------------------------------------
  # Normal operation — stable signal does not alert
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Upward shift detection
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Downward shift detection
  # -------------------------------------------------------

  test "sustained downward shift triggers :downward_shift alert" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 10, threshold: 3.0, slack: 0.5)

    for v <- [10.0, 10.1, 9.9, 10.2, 9.8, 10.0, 10.1, 9.9, 10.0, 10.1] do
      CusumAnomaly.push(c, "s", v)
    end

    outcomes = for _ <- 1..20, do: CusumAnomaly.push(c, "s", 2.0)

    assert Enum.any?(outcomes, &(&1 == {:alert, :downward_shift}))
  end

  # -------------------------------------------------------
  # State reset after alert
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset/2 clears the stream state" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 10.0)

    for v <- [1.0, 2.0, 3.0, 4.0], do: CusumAnomaly.push(c, "s", v)
    {:ok, info} = CusumAnomaly.check(c, "s")
    assert info.samples > 0

    :ok = CusumAnomaly.reset(c, "s")

    {:ok, info2} = CusumAnomaly.check(c, "s")
    assert info2.samples == 0
    assert info2.mean == 0.0
  end

  test "reset on unknown stream returns :ok without creating it" do
    {:ok, c} = CusumAnomaly.start_link()
    assert :ok = CusumAnomaly.reset(c, "ghost")

    # check/2 should still report :no_data
    assert {:error, :no_data} = CusumAnomaly.check(c, "ghost")
  end

  # -------------------------------------------------------
  # Stream independence
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Validation
  # -------------------------------------------------------

  test "invalid options raise at start_link" do
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(threshold: 0) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(threshold: -1) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(slack: -0.1) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(warmup_samples: 0) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(epsilon: 0) end
  end

  test "push rejects non-numeric" do
    {:ok, c} = CusumAnomaly.start_link()

    assert_raise FunctionClauseError, fn -> CusumAnomaly.push(c, "s", :nope) end
  end

  # -------------------------------------------------------
  # Inspection
  # -------------------------------------------------------

  test "check on unknown stream returns :no_data" do
    {:ok, c} = CusumAnomaly.start_link()
    assert {:error, :no_data} = CusumAnomaly.check(c, "never_seen")
  end

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

  test "below-slack stddev skips CUSUM and returns :ok despite a large spike" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 3.0, slack: 0.5)

    for _ <- 1..3, do: assert(:warming_up = CusumAnomaly.push(c, "s", 5.0))

    # stddev before this push is 0.0 (a flat signal), which is below slack,
    # so even a huge deviation must be absorbed with a plain :ok — no alert.
    assert :ok = CusumAnomaly.push(c, "s", 100.0)
  end

  test "default warmup_samples is 10 pushes" do
    {:ok, c} = CusumAnomaly.start_link()

    for _ <- 1..10, do: assert(:warming_up = CusumAnomaly.push(c, "s", 5.0))

    # The 11th push is the first CUSUM-active push (default warmup is 10).
    assert :ok = CusumAnomaly.push(c, "s", 5.0)
  end

  # -------------------------------------------------------
  # Live CUSUM accumulators are visible between pushes
  # -------------------------------------------------------

  test "check/2 reports the running s_high accumulated by non-alerting pushes" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 100.0, slack: 0.5)

    # Warmup leaves mean 10.0 and population stddev sqrt(8/3), which is
    # comfortably above slack, so the next push runs the CUSUM step.
    for v <- [10.0, 12.0, 8.0], do: assert(:warming_up = CusumAnomaly.push(c, "s", v))

    z1 = (20.0 - 10.0) / :math.sqrt(8 / 3)
    assert :ok = CusumAnomaly.push(c, "s", 20.0)

    {:ok, after_one} = CusumAnomaly.check(c, "s")
    assert after_one.status == :normal
    # s_high = max(0.0, 0.0 + z - slack) after a single upward deviation.
    assert close_to(after_one.s_high, z1 - 0.5, 1.0e-9)
    # A positive z can only drive s_low to max(0.0, -z - slack) = 0.0.
    assert after_one.s_low == 0.0

    # The second push z-scores against the mean/stddev that now include 20.0
    # and accumulates onto the surviving s_high rather than restarting it.
    z2 = (20.0 - 12.5) / :math.sqrt(83 / 4)
    assert :ok = CusumAnomaly.push(c, "s", 20.0)

    {:ok, after_two} = CusumAnomaly.check(c, "s")
    assert close_to(after_two.s_high, z1 - 0.5 + (z2 - 0.5), 1.0e-9)
    assert after_two.s_high > after_one.s_high
    assert after_two.s_low == 0.0
  end

  test "check/2 reports the running s_low accumulated by non-alerting pushes" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 100.0, slack: 0.5)

    for v <- [10.0, 12.0, 8.0], do: assert(:warming_up = CusumAnomaly.push(c, "s", v))

    z1 = (0.0 - 10.0) / :math.sqrt(8 / 3)
    assert :ok = CusumAnomaly.push(c, "s", 0.0)

    {:ok, after_one} = CusumAnomaly.check(c, "s")
    assert after_one.status == :normal
    # s_low = max(0.0, 0.0 - z - slack) after a single downward deviation.
    assert close_to(after_one.s_low, -z1 - 0.5, 1.0e-9)
    assert after_one.s_high == 0.0

    z2 = (0.0 - 7.5) / :math.sqrt(83 / 4)
    assert :ok = CusumAnomaly.push(c, "s", 0.0)

    {:ok, after_two} = CusumAnomaly.check(c, "s")
    assert close_to(after_two.s_low, -z1 - 0.5 + (-z2 - 0.5), 1.0e-9)
    assert after_two.s_low > after_one.s_low
    assert after_two.s_high == 0.0
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
