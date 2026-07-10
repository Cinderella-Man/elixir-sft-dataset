# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CusumAnomaly do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and detects
  change-points via a two-sided CUSUM algorithm backed by Welford's online
  mean/variance.

  On each push of `x`:

    1. If `samples < warmup_samples`, push to Welford and return `:warming_up`.
    2. Otherwise, z-score `x` against the **prior** mean/stddev:
         z = (x - mean) / max(stddev, epsilon)
    3. Update CUSUMs:
         s_high = max(0.0, s_high + z - slack)
         s_low  = max(0.0, s_low  - z - slack)
    4. Update Welford with `x`.
    5. If `s_high >= threshold`, emit `:upward_shift` and reset ALL state
       (Welford + both CUSUMs) so the detector re-learns the new regime.
    6. Likewise for `s_low >= threshold` → `:downward_shift` + reset.

  State per stream:

      %{
        samples:  non_neg_integer,
        mean:     float,
        m2:       float,             # Welford's sum of squared differences
        s_high:   float,
        s_low:    float
      }

  Global config (not per stream):

      %{threshold, slack, warmup_samples, epsilon}

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    validate!(threshold, slack, warmup, epsilon)

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Pushes `value` into the CUSUM detector for `name`. Returns `:ok` or a change signal."
  @spec push(GenServer.server(), term(), number()) ::
          :ok | :warming_up | {:alert, :upward_shift | :downward_shift}
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @spec check(GenServer.server(), term()) ::
          {:ok, map()} | {:error, :no_data}
  def check(server, name), do: GenServer.call(server, {:check, name})

  @spec reset(GenServer.server(), term()) :: :ok
  def reset(server, name), do: GenServer.call(server, {:reset, name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    {:ok,
     %{
       streams: %{},
       threshold: threshold,
       slack: slack,
       warmup_samples: warmup,
       epsilon: epsilon
     }}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = stream_for(state, name)
    value = value * 1.0

    cond do
      # Stream was alerted and is frozen until explicit reset.
      Map.get(stream, :alerted, false) ->
        {:reply, :warming_up, state}

      # Still warming up — update Welford only, no CUSUM yet.
      stream.samples < state.warmup_samples ->
        new_stream = welford_update(stream, value)
        {:reply, :warming_up, put_stream(state, name, new_stream)}

      # CUSUM-active but stddev is below the slack tolerance — z-scores
      # against such a tiny stddev are meaningless and cause false alerts.
      welford_stddev(stream) < state.slack ->
        post_welford = welford_update(stream, value)
        {:reply, :ok, put_stream(state, name, post_welford)}

      true ->
        # Z-score against the prior mean/stddev.
        prior_mean = stream.mean
        prior_std = max(welford_stddev(stream), state.epsilon)
        z = (value - prior_mean) / prior_std

        new_s_high = max(0.0, stream.s_high + z - state.slack)
        new_s_low = max(0.0, stream.s_low - z - state.slack)

        # Always update Welford AFTER z-scoring.
        post_welford = welford_update(stream, value)

        updated = %{post_welford | s_high: new_s_high, s_low: new_s_low}

        cond do
          new_s_high >= state.threshold ->
            {:reply, {:alert, :upward_shift}, put_stream(state, name, alerted_stream())}

          new_s_low >= state.threshold ->
            {:reply, {:alert, :downward_shift}, put_stream(state, name, alerted_stream())}

          true ->
            {:reply, :ok, put_stream(state, name, updated)}
        end
    end
  end

  def handle_call({:check, name}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        status = if stream.samples < state.warmup_samples, do: :warming_up, else: :normal

        info = %{
          mean: stream.mean,
          stddev: welford_stddev(stream),
          s_high: stream.s_high,
          s_low: stream.s_low,
          samples: stream.samples,
          status: status
        }

        {:reply, {:ok, info}, state}
    end
  end

  def handle_call({:reset, name}, _from, state) do
    new_streams =
      case Map.fetch(state.streams, name) do
        {:ok, _} -> Map.put(state.streams, name, reset_stream())
        :error -> state.streams
      end

    {:reply, :ok, %{state | streams: new_streams}}
  end

  # ---------------------------------------------------------------------------
  # Welford's online mean and variance
  # ---------------------------------------------------------------------------

  defp welford_update(stream, value) do
    n = stream.samples + 1
    delta = value - stream.mean
    new_mean = stream.mean + delta / n
    delta2 = value - new_mean
    new_m2 = stream.m2 + delta * delta2
    %{stream | samples: n, mean: new_mean, m2: new_m2}
  end

  defp welford_stddev(%{samples: 0}), do: 0.0
  defp welford_stddev(%{samples: n, m2: m2}), do: :math.sqrt(m2 / n)

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name), do: Map.get(state.streams, name, reset_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp reset_stream do
    %{samples: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0}
  end

  defp alerted_stream do
    %{samples: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0, alerted: true}
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp validate!(threshold, slack, warmup, epsilon) do
    if threshold <= 0.0, do: raise(ArgumentError, ":threshold must be positive")
    if slack < 0.0, do: raise(ArgumentError, ":slack must be non-negative")

    unless is_integer(warmup) and warmup > 0,
      do: raise(ArgumentError, ":warmup_samples must be a positive integer")

    if epsilon <= 0.0, do: raise(ArgumentError, ":epsilon must be positive")
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule CusumAnomalyTest do
  use ExUnit.Case, async: true

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
    # TODO
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
end
```
